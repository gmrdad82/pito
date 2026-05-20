require "rails_helper"

# Phase 29 (settings refactor) — system spec for the 3-row dashboard.
#
# Verifies:
#   * The page renders the new 3-row layout.
#   * Each security modal launcher opens a `<dialog>` (rack_test
#     cannot execute JS; system spec uses rack_test against the HTML
#     structure of the dialog markers).
#   * The profile form updates the username via the normal PATCH path.
#   * The dropped surfaces (UI/UX, Workspaces, Voyage.ai, install
#     timezone) are absent.
#
# 2026-05-19 — the theme system was removed alongside the single-theme
# cleanup; the inline bootstrap script + `pito-theme` localStorage key
# no longer exist in the layout. Negative guards below assert their
# absence.
RSpec.describe "Settings refactor — system shell", type: :system do
  before { driven_by(:rack_test) }

  let(:password) { "lucy-password-1" }
  let!(:user) do
    create(:user, username: "lucy", password: password, password_confirmation: password,
                  totp_enabled_at: Time.current,
                  totp_seed_encrypted: "JBSWY3DPEHPK3PXP")
  end

  before do
    sign_in_as(user)
  end

  it "renders the 3-row dashboard with security + Discord + Slack + stack panes (Phase F3: profile CUT to rake tasks)" do
    visit settings_path

    # Row 1 — Phase F3 (Beta 4, 2026-05-20) — profile pane removed
    # per ADR 0016. Username + password management moved to operator-
    # only rake tasks. Security pane is the sole row-1 surface.
    expect(page).to have_content("security")
    expect(page).to have_no_css("h2", text: /\Aprofile\z/)
    # Row 2 — Discord LEFT, Slack RIGHT (oauth + tokens moved to rake).
    expect(page).to have_content("Discord")
    expect(page).to have_content("Slack")
    expect(page).not_to have_content("OAuth applications")
    expect(page).to have_no_css("h2", text: /\Atokens\z/)
    # Row 3
    expect(page).to have_content("stack")
  end

  it "renders row 2 as two side-by-side .pane blocks (Discord LEFT, Slack RIGHT)" do
    visit settings_path
    body = page.body

    discord_idx = body.index("<h2>Discord</h2>")
    slack_idx   = body.index("<h2>Slack</h2>")
    stack_idx   = body.index('class="pito-pane__title">stack')
    expect(discord_idx).not_to be_nil
    expect(slack_idx).not_to be_nil
    expect(stack_idx).not_to be_nil
    # Discord appears before Slack — LEFT then RIGHT.
    expect(discord_idx).to be < slack_idx
    # Both row-2 headings appear before the row-3 stack pane.
    expect(slack_idx).to be < stack_idx

    # Phase F3 (Beta 4, 2026-05-20) — profile pane CUT per ADR 0016.
    # Before row 3 we now render Security (row 1) + Discord + Slack
    # (row 2) = three `<div class="pane">` openings.
    pane_openings_before_row3 = body[0...stack_idx].scan(/<div class="pane">/).size
    expect(pane_openings_before_row3).to be >= 3
  end

  it "renders the inline sessions table in the Security pane and the (TOTP-only) settings modal dialog" do
    visit settings_path
    # Phase 32 follow-up (2026-05-16) — `[ 2FA / TOTP ]` launcher
    # dropped along with the manage page.
    expect(page).not_to have_link("2FA / TOTP")
    # 2026-05-16 (sessions revamp v2) — the `[ sessions ]` launcher
    # is gone; the sessions table renders INLINE inside the Security
    # pane. The `[ locations ]` launcher was already dropped along
    # with the post-Phase-25 rollback.
    expect(page).not_to have_link("sessions")
    expect(page).not_to have_link("locations")
    # The Security pane mounts the sessions-bulk-revoke Stimulus
    # controller on its `<fieldset>` so the inline table's checkboxes
    # have a controller to talk to.
    expect(page.body).to include('data-controller="sessions-bulk-revoke"')
    # The TOTP-enrollment modal skeleton still lives on the page —
    # the mandatory-2FA gate auto-opens it via Turbo Frame.
    expect(page.body).to include('id="settings_modal_frame"')
    expect(page.body).to include('data-controller="settings-modal"')
  end

  it "does NOT render the dropped UI/UX, Workspace, Voyage.ai, or install-timezone panes" do
    visit settings_path
    expect(page.body).not_to include("<h2>ui / ux</h2>")
    expect(page.body).not_to include("<h2>workspaces</h2>")
    expect(page.body).not_to include("<h2>Voyage.ai</h2>")
    expect(page.body).not_to include("<h2>time zone</h2>")
    expect(page.body).not_to include('name="settings[max_panes]"')
    expect(page.body).not_to include('name="settings[pane_title_length]"')
    expect(page.body).not_to include('name="settings[theme]"')
    expect(page.body).not_to include('name="settings[keyboard_navigation_enabled]"')
  end

  it "does NOT render the dropped inline theme bootstrap script (removed 2026-05-19)" do
    visit settings_path
    # The localStorage-driven `pito-theme` bootstrap and the `theme`
    # Stimulus controller were removed alongside the single-theme
    # cleanup. The layout now ships `<html data-theme="dark">` as a
    # static literal; no script reads or writes the key.
    expect(page.body).not_to include("pito-theme")
  end

  it "does NOT render the dropped data-theme-preference attribute on <html>" do
    visit settings_path
    expect(page.body).not_to include("data-theme-preference")
  end

  it "does NOT render the dropped data-keyboard-navigation-enabled attribute on <body>" do
    visit settings_path
    expect(page.body).not_to include("data-keyboard-navigation-enabled")
  end

  it "does NOT render the dropped /settings/user profile form (Phase F3)" do
    # Phase F3 (Beta 4, 2026-05-20) — profile pane + /settings/user
    # surface cut per ADR 0016. Username + password management moved
    # to operator-only rake tasks (`bin/rails pito:user:rename`,
    # `bin/rails pito:user:password_set`).
    visit settings_path
    expect(page).to have_no_selector("form[action='/settings/user']")
    expect(page.body).not_to include('name="user[current_password]"')
    expect(page.body).not_to include('name="user[password_confirmation]"')
  end

  private

  def sign_in_as(user)
    visit login_path
    fill_in "username", with: user.username
    fill_in "password", with: password
    click_button "[log in]"
  end
end
