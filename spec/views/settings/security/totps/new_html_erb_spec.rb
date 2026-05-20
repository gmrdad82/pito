require "rails_helper"

# Beta 4 — Phase F3-DEEP-A (2026-05-20). TOTP enrollment view TUI revamp.
#
# Owns the focused enrollment dialog that the mandatory-2FA gate routes
# every fresh user through. The view is mounted with `content_for(
# :hide_chrome, true)` so the layout drops the status bar + footer
# while the user lives on this page; the only exits are the [verify]
# submit or the layout-level [logout] link (allowlisted by the gate).
#
# The TUI revamp lowered the H1 to lowercase (rendered at 13px bold via
# the single-font-size heading rule), wrapped the QR + backup-codes
# blocks in `Tui::FramedPanelComponent` (the bordered-section primitive
# with a title header), and wired the submit through the existing
# `Settings::TotpEnrollmentPaneComponent` which renders the bracketed
# `[verify]` action.
RSpec.describe "settings/security/totps/new.html.erb", type: :view do
  let(:totp_uri) { "otpauth://totp/pito:alice?secret=JBSWY3DPEHPK3PXP&issuer=pito" }
  let(:seed) { "JBSWY3DPEHPK3PXP" }
  let(:codes) do
    %w[
      11111111 22222222 33333333 44444444 55555555
      66666666 77777777 88888888 99999999 00000000
    ]
  end

  before do
    assign(:totp_uri, totp_uri)
    assign(:seed, seed)
    assign(:codes, codes)
    render template: "settings/security/totps/new", layout: false
  end

  describe "lowercase H1 + lead paragraphs" do
    it "renders the H1 as lowercase `enroll two-factor authentication`" do
      # ADR 0016 single-font-size heading rule means H1 is rendered
      # bold at 13px; the copy itself is lowercase per the TUI revamp.
      expect(rendered).to include("<h1>enroll two-factor authentication</h1>")
    end

    it "renders the danger-tinted requires lines from i18n" do
      expect(rendered).to include("pito requires 2FA.")
      expect(rendered).to include("nothing else is reachable until 2FA is enabled.")
      # The two lines render inside a `text-danger` paragraph so the
      # gate-blocking warning reads at a glance.
      expect(rendered).to match(/class="text-danger"[\s\S]*pito requires 2FA/)
    end

    it "renders the muted authenticator-app hint line" do
      expect(rendered).to include("scan the QR with")
      expect(rendered).to match(/text-muted[\s\S]*scan the QR with/)
    end
  end

  describe "scan QR pane (Settings::TotpEnrollmentPaneComponent)" do
    it "renders the enrollment pane component (QR + seed + code form)" do
      # The pane component owns its own HTML; verify by way of the
      # contract elements the component renders (white-bg QR wrapper +
      # seed in a <pre>).
      expect(rendered).to have_css('div[style*="background: #ffffff"][style*="display: inline-block"]')
      expect(rendered).to have_css("pre", text: seed)
    end

    it "renders the `[verify]` submit button (post-F3-DEEP-A label)" do
      expect(rendered).to have_css(
        'button[type="submit"].bracketed span.bl', text: "verify"
      )
    end

    it "posts the form to /settings/security/totp" do
      expect(rendered).to have_css('form[action="/settings/security/totp"][method="post"]')
    end
  end

  describe "backup codes panel (Tui::FramedPanelComponent)" do
    it "wraps the backup codes block in the framed-panel primitive" do
      # `Tui::FramedPanelComponent` renders a `<section class=
      # "tui-framed-panel">` with a `<header class="tui-framed-panel__
      # title">` carrying the panel title and a `<div class=
      # "tui-framed-panel__body">` for the content.
      expect(rendered).to have_css(
        "section.tui-framed-panel header.tui-framed-panel__title",
        text: "backup codes"
      )
    end

    it "renders all ten backup codes inside the framed panel" do
      codes.each do |code|
        expect(rendered).to include(code)
      end
    end

    it "renders the codes in a `<pre>` block with tabular-nums alignment" do
      expect(rendered).to match(/<pre[^>]*tabular-nums/)
    end

    it "renders the muted backup-codes hint copy" do
      expect(rendered).to include("each code works once.")
      expect(rendered).to include("store them somewhere safe")
    end
  end

  describe "non-resumable layout contract" do
    it "renders inside the settings_modal_frame turbo-frame" do
      # The view wraps itself in `turbo_frame_tag :settings_modal_frame`
      # so a click from /settings auto-open swaps it cleanly into the
      # mandatory-2FA modal. Direct hits render the same content inside
      # the layout's <main>.
      expect(rendered).to include('id="settings_modal_frame"')
    end

    it "does NOT render a cancel link (gate-blocking enrollment)" do
      # The only escape paths are the [verify] submit or the global
      # [logout] link in the layout. There is no inline cancel button.
      expect(rendered).not_to include(">cancel<")
    end
  end

  describe "no forbidden JS confirm hooks" do
    it "does NOT render data-turbo-confirm" do
      expect(rendered).not_to include("data-turbo-confirm")
    end
  end
end
