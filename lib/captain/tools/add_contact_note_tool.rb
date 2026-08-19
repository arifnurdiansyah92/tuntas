class Captain::Tools::AddContactNoteTool < Captain::Tools::BasePublicTool
  description 'Add a note to a contact profile'
  param :note, type: 'string', desc: 'The note content to add to the contact'

  def perform(tool_context, note:)
    return 'Note content is required' if note.blank?

    contact = find_contact(tool_context.state)
    return 'Contact not found' if contact.blank?

    contact.notes.create!(
      account: assistant.account,
      user: assistant.account.users.first,
      content: note
    )
    log_tool_usage('add_contact_note', { contact_id: contact.id, note_length: note.length })

    "Note added successfully to contact #{contact.name} (ID: #{contact.id})"
  end
end
