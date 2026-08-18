json.payload do
  json.array! @applied_slas do |applied_sla|
    json.applied_sla applied_sla.push_event_data
    json.conversation applied_sla.conversation.push_event_data
  end
end

json.meta do
  json.count @applied_slas.count
end
