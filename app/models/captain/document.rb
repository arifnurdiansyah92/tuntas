# == Schema Information
#
# Table name: captain_documents
#
#  id                     :bigint           not null, primary key
#  content                :text
#  external_link          :text             not null
#  last_sync_attempted_at :datetime
#  last_synced_at         :datetime
#  metadata               :jsonb
#  name                   :string
#  status                 :integer          default("in_progress"), not null
#  sync_status            :integer
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  assistant_id           :bigint           not null
#
class Captain::Document < ApplicationRecord
  self.table_name = 'captain_documents'

  MAX_PDF_SIZE = 10.megabytes
  PDF_LINK_PREFIX = 'PDF: '.freeze
  PRIVATE_IPV6_PREFIXES = %w[fc fd fe8 fe9 fea feb].freeze

  belongs_to :assistant, class_name: 'Captain::Assistant', inverse_of: :documents
  belongs_to :account
  has_many :responses, class_name: 'Captain::AssistantResponse', as: :documentable, dependent: :destroy_async

  has_one_attached :pdf_file

  enum :status, { in_progress: 0, available: 1 }

  validates :external_link, presence: true
  validate :validate_pdf_file_size

  before_validation :normalize_external_link
  before_validation :ensure_pdf_external_link
  after_save :enqueue_response_builder

  def pdf_document?
    return true if pdf_file.attached?
    return false if external_link.blank?

    external_link.start_with?(PDF_LINK_PREFIX) || external_link.end_with?('.pdf') || pdf_url?
  end

  def display_url
    return Rails.application.routes.url_helpers.rails_blob_url(pdf_file, only_path: false) if pdf_file.attached?

    external_link
  end

  def openai_file_id
    metadata&.dig('openai_file_id')
  end

  def store_openai_file_id(file_id)
    update!(metadata: (metadata || {}).merge('openai_file_id' => file_id))
  end

  # Returns the external link only when it is a safe, customer-shareable public URL.
  def customer_visible_source_url
    return if external_link.blank?

    uri = URI.parse(external_link)
    return unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    return if uri.userinfo.present?
    return unless publicly_resolvable?(uri.host)

    external_link
  rescue URI::InvalidURIError
    nil
  end

  private

  def pdf_url?
    uri = URI.parse(external_link)
    uri.path.to_s.end_with?('.pdf')
  rescue URI::InvalidURIError
    false
  end

  def publicly_resolvable?(host)
    addresses = Resolv.getaddresses(host)
    return false if addresses.blank?

    addresses.all? { |address| public_address?(address) }
  end

  def public_address?(address)
    ip = IPAddr.new(address)
    !(ip.private? || ip.loopback? || ip.link_local?)
  rescue IPAddr::InvalidAddressError
    false
  end

  def normalize_external_link
    self.external_link = external_link.chomp('/') if external_link.present?
  end

  def ensure_pdf_external_link
    return if external_link.present?
    return unless pdf_file.attached?

    base_name = pdf_file.filename.base.to_s.parameterize(separator: '_')
    self.external_link = "#{PDF_LINK_PREFIX}#{base_name}_#{Time.zone.now.strftime('%Y%m%d%H%M%S')}"
  end

  def validate_pdf_file_size
    return unless pdf_file.attached?
    return if pdf_file.blob.byte_size <= MAX_PDF_SIZE

    errors.add(:pdf_file, I18n.t('captain.documents.pdf_size_error'))
  end

  def enqueue_response_builder
    return unless available?
    return unless pdf_document? ? pdf_response_build_needed? : content_response_build_needed?

    Captain::Documents::ResponseBuilderJob.perform_later(self)
  end

  def pdf_response_build_needed?
    previously_new_record? || saved_change_to_status?
  end

  def content_response_build_needed?
    content.present? && (previously_new_record? || saved_change_to_status? || saved_change_to_content?)
  end
end
