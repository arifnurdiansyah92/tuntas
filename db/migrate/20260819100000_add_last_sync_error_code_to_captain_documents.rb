class AddLastSyncErrorCodeToCaptainDocuments < ActiveRecord::Migration[7.2]
  def change
    add_column :captain_documents, :last_sync_error_code, :string
  end
end
