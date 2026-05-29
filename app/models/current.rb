class Current < ActiveSupport::CurrentAttributes
  # Z1 (2026-05-25) — `user` dropped with the `users` table. pito is
  # single-install; the owner is identified solely by the active session.
  # `token` is kept for API (Bearer) surfaces; `session` is the cookie
  # session pin.
  attribute :session, :token
end
