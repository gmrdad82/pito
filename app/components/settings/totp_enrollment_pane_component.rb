module Settings
  # Renders the LEFT pane of the mandatory-2FA enrollment screen — the
  # QR-code scan block, the seed fallback, and the 6-digit enter-code
  # form that POSTs to `settings_security_totp_path`.
  #
  # Extracted from `app/views/settings/security/totps/new.html.erb`
  # (lines 64-106) per Beta-3 lane B candidate B11. The right-pane
  # backup-codes block is intentionally NOT part of this component —
  # it stays inline in the parent template.
  #
  # The QR wrapper preserves the `background: #ffffff` +
  # `display: inline-block` invariant so the SVG (black modules on
  # transparent) reads against the dark theme — a contrast-fix polish
  # the spec for this component locks down.
  class TotpEnrollmentPaneComponent < ViewComponent::Base
    def initialize(totp_uri:, seed:)
      @totp_uri = totp_uri
      @seed = seed
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
