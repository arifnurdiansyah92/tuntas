class AuditLog < Audited::Audit
  scope :for_account, lambda { |account_id|
    where(associated_type: 'Account', associated_id: account_id)
      .or(where(auditable_type: 'Account', auditable_id: account_id))
  }
end
