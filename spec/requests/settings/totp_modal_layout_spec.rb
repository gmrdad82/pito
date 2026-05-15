require "rails_helper"

# 2026-05-11 — Layout-level TOTP verification modal contract.
#
# The four settings panes the fresh-TOTP gate guards (YouTube,
# Voyage.ai, Discord, Slack) used to render an inline `2FA code` text
# input above their `[update]` button. Per user direction 2026-05-11
# the inline fields are gone; clicking `[update]` opens a
# layout-level modal with a Slack-style 6-box segmented input. The
# modal auto-submits the pending form the instant all 6 digits are
# present (typed or pasted) — no `[confirm]` button, no manual
# trigger. `[cancel]` (and Esc / backdrop) drop the dialog without
# submitting.
#
# This spec is the markup contract the Stimulus controllers
# (`totp-modal` + `totp-modal-dialog`) depend on. The project does
# not run JS in specs, so the segmented-input behaviour itself is
# covered by manual validation; we lock the DOM here.
RSpec.describe "TOTP verification modal layout integration", type: :request do
  let(:password) { "supersecret123" }
  let(:seed) { "JBSWY3DPEHPK3PXP" }
  let(:user) do
    User.first || create(:user, password: password, password_confirmation: password)
  end

  def enable_two_factor!
    user.update!(totp_seed_encrypted: seed, totp_enabled_at: 1.hour.ago)
    user.update_columns(totp_last_used_step: nil, totp_disabled_at: nil)
  end

  def disable_two_factor!
    user.update!(totp_seed_encrypted: nil, totp_enabled_at: nil)
  end

  describe "the layout-level dialog" do
    before { sign_in_as(user) }

    it "is rendered on /settings for an authenticated user" do
      get settings_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="totp-verification-modal"')
      expect(response.body).to include('data-controller="totp-modal-dialog"')
    end

    it "renders six segmented boxes targeted by the dialog controller" do
      get settings_path
      # Each box carries the Stimulus target on the dialog controller
      # plus a per-box input / keydown / paste action wiring. The
      # partial inlines `data-action` as raw HTML so the literal
      # `->` survives untouched. Match either form to stay resilient
      # to escaping if someone migrates to a Rails tag helper.
      expect(response.body.scan(/data-totp-modal-dialog-target="box"/).size).to eq(6)
      expect(response.body).to match(/input(->|-&gt;)totp-modal-dialog#onInput/)
      expect(response.body).to match(/keydown(->|-&gt;)totp-modal-dialog#onKeydown/)
      expect(response.body).to match(/paste(->|-&gt;)totp-modal-dialog#onPaste/)
    end

    it "renders the bracketed [cancel] button (no [confirm], auto-submit on 6th digit)" do
      get settings_path
      # `[cancel]` stays as the explicit escape hatch alongside Esc /
      # backdrop. `[confirm]` is gone — the modal auto-submits the
      # pending form the instant the 6th digit lands.
      expect(response.body).to include("totp-modal-dialog#close")
      # Bracketed-link convention (`[label]`, no inner spaces) — the
      # button surfaces the `<span class="bl">` glyph pattern.
      expect(response.body).to match(/\[<span class="bl">cancel<\/span>\]/)
      # Negative assertions — no [confirm] button, no Stimulus
      # confirm target, no `#confirm` action wired anywhere.
      expect(response.body).not_to include('data-totp-modal-dialog-target="confirm"')
      expect(response.body).not_to include("totp-modal-dialog#confirm")
      expect(response.body).not_to match(/\[<span class="bl">confirm<\/span>\]/)
    end

    it "wires the segmented input so auto-submit fires on the 6th digit" do
      # Auto-submit fires from `_maybeAutoSubmit()` inside the
      # `onInput` and `onPaste` handlers in the dialog controller.
      # The DOM contract this spec locks: every box wires both
      # `input->...#onInput` (auto-submit on the 6th typed digit) and
      # `paste->...#onPaste` (auto-submit when 6 digits are pasted in
      # at once). Neither path requires a button click.
      get settings_path
      box_block = response.body[/<div class="totp-modal-boxes">.*?<\/div>/m]
      expect(box_block).to be_present
      expect(box_block.scan(/input(?:->|-&gt;)totp-modal-dialog#onInput/).size).to eq(6)
      expect(box_block.scan(/paste(?:->|-&gt;)totp-modal-dialog#onPaste/).size).to eq(6)
    end

    it "is NOT rendered on an unauthenticated screen" do
      # /login renders the layout without `Current.user`, so the
      # conditional render bails out and the dialog markup is absent.
      get "/login"
      expect(response.body).not_to include('id="totp-verification-modal"')
    end
  end

  describe "settings pane forms when 2FA is on" do
    before do
      enable_two_factor!
      sign_in_as(user)
    end

    it "YouTube pane form carries the totp-modal controller wiring" do
      get settings_path
      expect(response.body).to match(
        /<form[^>]*data-controller="totp-modal"[^>]*data-totp-modal-required-value="yes"/m
      )
      # ERB escapes `->` to `-&gt;` in attribute output.
      expect(response.body).to include("submit-&gt;totp-modal#maybeIntercept")
    end

    it "Voyage pane form carries the totp-modal controller wiring" do
      get settings_path
      # Two of the three settings-path PATCH forms (youtube + voyage)
      # surface `required="yes"`; the third (workspaces/appearance)
      # never opts in. Count by required attribute.
      count = response.body.scan(/data-totp-modal-required-value="yes"/).size
      # YouTube + Voyage on the index; Slack + Discord render on the
      # _slack_pane / _discord_pane partials which are NOT mounted on
      # this page per the 2026-05-10 index layout. The integrations
      # row 2 was dropped earlier, so the index has exactly two
      # required="yes" forms.
      expect(count).to be >= 2
    end

    it "does NOT render an inline `name=\"totp_code\"` text input in any settings pane" do
      get settings_path
      # The four pane partials we migrated must not surface the inline
      # field anymore. The user/edit page keeps its own inline field
      # (out of scope for this migration) so a broader sweep would
      # false-positive against `/settings/user`.
      expect(response.body).not_to include('id="settings_youtube_totp_code"')
      expect(response.body).not_to include('id="settings_voyage_totp_code"')
    end
  end

  describe "settings pane forms when 2FA is off" do
    # Phase 29 — Unit A2. The mandatory-2FA gate means a 2FA-off
    # authenticated user can never reach `/settings` — the gate
    # bounces them to the TOTP enrollment page first. The
    # `required="no"` settings-pane markup is therefore unreachable on
    # the web; the only observable contract for a 2FA-off user on
    # `/settings` is the gate redirect. The `required="no"` wiring
    # itself is still locked by the Slack/Discord partial block below,
    # which renders the partials in isolation past the gate.
    before do
      disable_two_factor!
      sign_in_as(user)
    end

    it "redirects /settings to the TOTP enrollment page (mandatory-2FA gate)" do
      get settings_path
      expect(response).to redirect_to(settings_security_totp_path)
    end
  end

  describe "Slack + Discord pane partials (rendered in isolation)" do
    # The pane partials read `Current.user&.totp_enabled?` to decide
    # the `required` wire value. `ApplicationController.render` does
    # not run the per-request middleware that sets `Current.user`, so
    # we pin it manually before rendering. Resetting in `ensure` keeps
    # later examples clean.
    def render_partial(path, locals: {})
      Current.user = user
      ApplicationController.render(partial: path, assigns: locals)
    ensure
      Current.user = nil
    end

    it "Slack pane no longer renders an inline `2FA code` input" do
      enable_two_factor!
      rendered = render_partial("settings/slack_pane", locals: { slack_webhook: nil })
      expect(rendered).not_to include('id="slack_totp_code"')
      expect(rendered).to include("submit-&gt;totp-modal#maybeIntercept")
      expect(rendered).to include('data-totp-modal-required-value="yes"')
    end

    it "Discord pane no longer renders an inline `2FA code` input" do
      enable_two_factor!
      rendered = render_partial("settings/discord_pane", locals: { discord_webhook: nil })
      expect(rendered).not_to include('id="discord_totp_code"')
      expect(rendered).to include("submit-&gt;totp-modal#maybeIntercept")
      expect(rendered).to include('data-totp-modal-required-value="yes"')
    end

    it "Slack pane carries `required=\"no\"` when 2FA is off" do
      disable_two_factor!
      rendered = render_partial("settings/slack_pane", locals: { slack_webhook: nil })
      expect(rendered).to include('data-totp-modal-required-value="no"')
    end

    it "Discord pane carries `required=\"no\"` when 2FA is off" do
      disable_two_factor!
      rendered = render_partial("settings/discord_pane", locals: { discord_webhook: nil })
      expect(rendered).to include('data-totp-modal-required-value="no"')
    end
  end

  # The wire-side contract — `totp_code` still lands on the controller
  # via `params[:totp_code]` — is already locked by
  # `spec/requests/settings/totp_gates_spec.rb`. This spec stays
  # focused on the layout markup the Stimulus controllers depend on.
end
