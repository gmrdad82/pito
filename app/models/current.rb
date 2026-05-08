class Current < ActiveSupport::CurrentAttributes
  # Phase 12 — Step A added `:session` so the HTML auth concern can pin
  # the active server-side session row. `Current.session` is what the
  # /settings/sessions index reads to render the "(this session)"
  # annotation; controllers can also reach it for audit-line metadata.
  attribute :tenant, :user, :token, :session

  # Phase 5A — convenience reader used by `BelongsToTenant`'s default
  # scope. Returns `Current.tenant&.id` so callers can branch on
  # presence (`if Current.tenant_id`) without a `respond_to?` dance.
  def tenant_id
    tenant&.id
  end
end
