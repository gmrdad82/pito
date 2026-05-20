require "rails_helper"

RSpec.describe Settings::TotpEnrollmentPaneComponent, type: :component do
  let(:totp_uri) { "otpauth://totp/pito:alice?secret=JBSWY3DPEHPK3PXP&issuer=pito" }
  let(:seed) { "JBSWY3DPEHPK3PXP" }

  before { render_inline(described_class.new(totp_uri: totp_uri, seed: seed)) }

  it "wraps the QR in a white-bg inline-block (dark-mode contrast invariant)" do
    expect(page).to have_css(
      'div[style*="background: #ffffff"][style*="display: inline-block"]'
    )
  end

  it "renders an <svg> inside the QR wrapper (proxy that RQRCode rendered)" do
    expect(page).to have_css(
      'div[style*="background: #ffffff"] svg', visible: :all
    )
  end

  it "renders the seed verbatim inside the <pre> fallback block" do
    expect(page).to have_css("pre", text: seed)
  end

  it "posts the enter-code form to settings_security_totp_path (/settings/security/totp)" do
    expect(page).to have_css('form[action="/settings/security/totp"][method="post"]')
  end

  it "uses form_with so Rails CSRF protection is engaged (no opt-out)" do
    # `render_inline` does not engage the controller's
    # `protect_against_forgery` instrumentation, so the rendered HTML
    # does NOT contain the authenticity_token <input> the live page
    # emits. What we CAN lock down here is that the form is not
    # opting out of CSRF — i.e. there is no `authenticity_token=false`
    # render path and no `data-turbo` Turbo-Stream submission that
    # would route around the token check. The form_with above sets
    # `data-turbo="false"`, so a real submission goes through the
    # standard Rails CSRF-protected POST.
    expect(page).to have_css('form[action="/settings/security/totp"][data-turbo="false"]')
    expect(page).to have_no_css('form[authenticity_token="false"]')
  end

  it "renders the 6-box segmented code input (TotpCodeInputComponent)" do
    # The enter-code form embeds `TotpCodeInputComponent` so the user
    # types the 6-digit code into a Slack-style segmented grid instead
    # of a single bare text input. Lock down the structural contract
    # here so a regression in the consuming component is caught at the
    # pane-level spec too.
    expect(page).to have_css(
      'div[data-controller="totp-code-input"]', visible: :all
    )
    expect(page).to have_css(
      'input[data-totp-code-input-target="digit"]',
      count: 6, visible: :all
    )
    expect(page).to have_css(
      'input[type="hidden"][name="code"][data-totp-code-input-target="hidden"]',
      visible: :all
    )
  end

  # 2026-05-20 — Beta 4 Phase F3-DEEP-A. The enrollment pane submit
  # label moved from `[enable 2FA]` to `[verify]` so the TUI revamp
  # treats the action as a single verb (matches the broader `[verify]`
  # / `[update]` / `[reindex]` vocabulary across the pane family).
  it "renders the [verify] submit button" do
    expect(page).to have_css('button[type="submit"].bracketed', text: "verify")
  end

  it "wraps the [verify] label text in a span.bl (bracketed-link convention)" do
    expect(page).to have_css('button[type="submit"].bracketed span.bl', text: "verify")
  end
end
