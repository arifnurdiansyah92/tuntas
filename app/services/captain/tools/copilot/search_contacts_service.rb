class Captain::Tools::Copilot::SearchContactsService < Captain::Tools::BaseService
  RESULT_LIMIT = 25

  def name
    'search_contacts'
  end

  def description
    'Search contacts based on query parameters'
  end

  def parameters
    {
      email: {
        type: 'string',
        description: 'Filter contacts by email address'
      },
      phone_number: {
        type: 'string',
        description: 'Filter contacts by phone number'
      },
      name: {
        type: 'string',
        description: 'Filter contacts by name (partial match)'
      }
    }
  end

  def execute(email: nil, phone_number: nil, name: nil)
    contacts = filtered_contacts(email, phone_number, name).limit(RESULT_LIMIT)
    return 'No contacts found' if contacts.blank?

    sections = ["Total number of contacts: #{contacts.size}"]
    sections += contacts.map(&:to_llm_text)
    sections.join("\n\n")
  end

  def active?
    user_has_permission?('contact_manage')
  end

  private

  def filtered_contacts(email, phone_number, name)
    contacts = account.contacts
    contacts = contacts.where(email: email) if email.present?
    contacts = contacts.where(phone_number: phone_number) if phone_number.present?
    contacts = contacts.where('contacts.name ILIKE ?', "%#{ActiveRecord::Base.sanitize_sql_like(name)}%") if name.present?
    contacts
  end
end
