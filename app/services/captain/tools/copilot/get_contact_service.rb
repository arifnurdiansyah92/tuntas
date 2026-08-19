class Captain::Tools::Copilot::GetContactService < Captain::Tools::BaseService
  def name
    'get_contact'
  end

  def description
    'Get details of a contact including their profile information'
  end

  def parameters
    {
      contact_id: {
        type: 'number',
        description: 'The ID of the contact to fetch'
      }
    }
  end

  def execute(contact_id: nil)
    contact = account.contacts.find_by(id: contact_id) if contact_id.present?
    return 'Contact not found' if contact.blank?

    contact.to_llm_text
  end

  def active?
    user_has_permission?('contact_manage')
  end
end
