# Phase 25 — 01e. TOTP UI helpers.
#
# Centralised issuer string + label format so the enrollment view,
# the QR code component, and the model's `totp_uri` all agree on
# what shows up in the user's authenticator app.
module TotpHelper
  TOTP_ISSUER = "pito"

  def totp_issuer
    TOTP_ISSUER
  end
end
