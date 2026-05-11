require "rails_helper"

# Phase 25 — 01b (LD-17). Two-button choice surface.
RSpec.describe LoginChallengeChoiceComponent, type: :component do
  it "renders the [enter 2FA code] bracketed choice" do
    render_inline(described_class.new)
    expect(page).to have_text("[enter 2FA code]")
  end

  it "renders the [ask for approval] bracketed choice" do
    render_inline(described_class.new)
    expect(page).to have_text("[ask for approval]")
  end

  it "uses no inner whitespace inside the brackets (no [ label ] form)" do
    render_inline(described_class.new)
    # If a future regression adds spaces inside the brackets, this
    # spec catches it.
    expect(page).not_to have_text(/\[ enter 2FA code \]/)
    expect(page).not_to have_text(/\[ ask for approval \]/)
  end

  it "posts to /login/challenge with the challenge_path hidden field" do
    render_inline(described_class.new)
    expect(page).to have_css('form[action="/login/challenge"]', count: 2)
    expect(page).to have_css('input[name="challenge_path"][value="totp"]', visible: false)
    expect(page).to have_css('input[name="challenge_path"][value="approval"]', visible: false)
  end
end
