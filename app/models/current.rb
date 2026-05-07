class Current < ActiveSupport::CurrentAttributes
  attribute :tenant, :user, :token

  # Phase 5A — convenience reader used by `BelongsToTenant`'s default
  # scope. Returns `Current.tenant&.id` so callers can branch on
  # presence (`if Current.tenant_id`) without a `respond_to?` dance.
  def tenant_id
    tenant&.id
  end
end
