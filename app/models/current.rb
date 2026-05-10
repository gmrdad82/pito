class Current < ActiveSupport::CurrentAttributes
  # Phase 8 — tenant drop. After ADR 0003, `Current.tenant` is gone:
  # pito is a single-install, multi-user surface and tenant scoping
  # collapses. The only request-scoped attributes left are the cookie
  # session pin (`:session`), the resolved user (`:user`), and the
  # bearer token (`:token`) for API surfaces.
  attribute :user, :token, :session
end
