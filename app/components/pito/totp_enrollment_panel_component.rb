module Pito
  # Panel: TOTP enrollment — QR-code scan block + seed fallback + 6-digit
  # verification form that POSTs to `settings_security_totp_path`.
  #
  # kwargs:
  #   totp_uri: String  — otpauth:// URI rendered as QR code
  #   seed:     String  — base32 seed shown as plaintext fallback
  #
  # variants: none
  #
  # focusables (2):
  #   1. code input  — Tui::TotpCodeComponent(mode: :digits, autofocus: true)
  #   2. [verify]    — form submit action (bracketed button)
  #
  # cable: pito:home:totp_enrollment
  #
  # composes: Tui::FramedPanelComponent, Tui::TotpCodeComponent
  #
  # Extracted from `app/views/settings/security/totps/new.html.erb`
  # (lines 64-106) per Beta-3 lane B candidate B11. The right-panel
  # backup-codes block is intentionally NOT part of this component —
  # it stays inline in the parent template.
  #
  # The QR wrapper preserves the `background: #ffffff` +
  # `display: inline-block` invariant so the SVG (black modules on
  # transparent) reads against the dark theme — a contrast-fix polish
  # the spec for this component locks down.
  class TotpEnrollmentPanelComponent < ViewComponent::Base
    CABLE_CHANNEL = "pito:home:totp_enrollment".freeze
    def initialize(totp_uri:, seed:)
      @totp_uri = totp_uri
      @seed = seed
    end

    def focusables
      [
        { id: "totp_code",  label: "code input",  kind: :input  },
        { id: "totp_verify", label: "[verify]",   kind: :action }
      ]
    end

    def qr_svg
      @qr_svg ||= RQRCode::QRCode.new(@totp_uri).as_svg(
        offset: 0,
        color: "000",
        shape_rendering: "crispEdges",
        module_size: 4,
        standalone: true
      ).html_safe
    end
  end
end
