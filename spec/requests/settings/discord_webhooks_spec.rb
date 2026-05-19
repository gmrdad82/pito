require "rails_helper"

# Phase 26 — 01c. Discord webhook pane request surface.
#
# `PATCH /settings/discord_webhook` validates the URL regex, fires a
# test ping via `Webhooks::DiscordClient`, and only persists the row
# when the ping returns 2xx. Booleans cross the wire as "yes"/"no"
# per CLAUDE.md hard rules.
#
# 2026-05-16 — recent-TOTP gate dropped from this surface. The
# `totp_code` PATCH parameter is no longer read by the controller;
# saves are plain saves.
RSpec.describe "Settings::DiscordWebhooks", type: :request do
  let(:valid_url) { "https://discord.com/api/webhooks/123456789012345678/abc-DEF_xyz123" }
  let(:legacy_url) { "https://discordapp.com/api/webhooks/123456789012345678/abc-DEF_xyz123" }

  describe "PATCH /settings/discord_webhook" do
    context "with a valid URL and a successful test ping" do
      before do
        stub_request(:post, valid_url).to_return(status: 204, body: "")
      end

      it "creates the install-level row" do
        expect {
          patch settings_discord_webhook_path,
                params: { discord_webhook_url: valid_url, everything: "yes", daily_digest: "no" }
        }.to change { NotificationDeliveryChannel.where(kind: "discord").count }.by(1)
      end

      it "persists `webhook_url` + `last_validated_at` (routing flags owned by NotificationTogglesController)" do
        # 2026-05-17 form restructure — the brand pane URL form only owns
        # the URL surface. `everything` and `daily_digest` moved to the
        # per-flag auto-save toggles handled by
        # `Settings::NotificationTogglesController`. Posting them here is a
        # no-op; the columns retain their database defaults (false).
        patch settings_discord_webhook_path,
              params: { discord_webhook_url: valid_url, everything: "yes", daily_digest: "yes" }

        record = NotificationDeliveryChannel.find_by(kind: "discord")
        expect(record.webhook_url).to eq(valid_url)
        expect(record.everything).to be(false)
        expect(record.daily_digest).to be(false)
        expect(record.last_validated_at).to be_within(5.seconds).of(Time.current)
      end

      it "redirects back to /settings with a notice" do
        patch settings_discord_webhook_path,
              params: { discord_webhook_url: valid_url, everything: "yes", daily_digest: "no" }
        expect(response).to redirect_to(settings_path)
        expect(flash[:notice]).to match(/Discord updated/)
      end

      it "fires exactly one test ping with the locked copy" do
        ping_stub = stub_request(:post, valid_url)
          .with(body: { "content" => "Pito test ping — Discord webhook configured." }.to_json)
          .to_return(status: 204, body: "")
        patch settings_discord_webhook_path,
              params: { discord_webhook_url: valid_url, everything: "no", daily_digest: "no" }
        expect(ping_stub).to have_been_requested.once
      end

      it "updates the existing row on a second save (no second row)" do
        # Pre-seed with flags=true to confirm the URL form does NOT touch
        # them on update (the flags are owned by NotificationTogglesController).
        NotificationDeliveryChannel.create!(
          kind: "discord", webhook_url: valid_url,
          everything: true, daily_digest: true
        )
        expect {
          patch settings_discord_webhook_path,
                params: { discord_webhook_url: valid_url, everything: "no", daily_digest: "no" }
        }.not_to change { NotificationDeliveryChannel.where(kind: "discord").count }
        record = NotificationDeliveryChannel.find_by(kind: "discord")
        expect(record.everything).to be(true)
        expect(record.daily_digest).to be(true)
      end

      it "stores `everything`/`daily_digest` as false when the form omits them" do
        patch settings_discord_webhook_path,
              params: { discord_webhook_url: valid_url }
        record = NotificationDeliveryChannel.find_by(kind: "discord")
        expect(record.everything).to be(false)
        expect(record.daily_digest).to be(false)
      end

      it "stores `everything`/`daily_digest` as false on 'no' strings" do
        patch settings_discord_webhook_path,
              params: { discord_webhook_url: valid_url, everything: "no", daily_digest: "no" }
        record = NotificationDeliveryChannel.find_by(kind: "discord")
        expect(record.everything).to be(false)
        expect(record.daily_digest).to be(false)
      end

      it "rejects raw Boolean wire values (true/false) as 'no'" do
        # Yes/no boundary — only the strings "yes"/"no" are valid. Anything
        # else (including the Boolean strings) coerces to false.
        patch settings_discord_webhook_path,
              params: { discord_webhook_url: valid_url, everything: "true", daily_digest: "1" }
        record = NotificationDeliveryChannel.find_by(kind: "discord")
        expect(record.everything).to be(false)
        expect(record.daily_digest).to be(false)
      end

      it "accepts the legacy discordapp.com host form" do
        stub_request(:post, legacy_url).to_return(status: 204, body: "")
        patch settings_discord_webhook_path,
              params: { discord_webhook_url: legacy_url }
        record = NotificationDeliveryChannel.find_by(kind: "discord")
        expect(record).to be_present
        expect(record.webhook_url).to eq(legacy_url)
      end

      it "isolates state from the Slack row" do
        # The two providers have independent rows keyed on `kind`. A
        # Discord save must NOT touch any pre-existing Slack row.
        slack_url = "https://hooks.slack.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567"
        slack = NotificationDeliveryChannel.create!(
          kind: "slack", webhook_url: slack_url,
          everything: true, daily_digest: true
        )
        patch settings_discord_webhook_path,
              params: { discord_webhook_url: valid_url, everything: "no", daily_digest: "no" }
        slack.reload
        expect(slack.webhook_url).to eq(slack_url)
        expect(slack.everything).to be(true)
        expect(slack.daily_digest).to be(true)
      end
    end

    # 2026-05-17 webhook URL hardening — input value masking.
    # The Discord pane no longer renders the real webhook URL in the
    # input's `value=""`. The field always submits empty unless the
    # operator types something new, so the controller's blank-URL
    # branch became a no-op ("leave alone") instead of the prior
    # "clear the integration" gesture — otherwise every page-level
    # save would have wiped the URL silently.
    #
    # The literal word "clear" is the cooperating gesture for the
    # clear-the-integration path. Whitespace-only submissions strip
    # down to blank and therefore also no-op.
    context "with a blank URL — no-op (preserve existing URL)" do
      it "does NOT create a row on a fresh blank submission" do
        expect {
          patch settings_discord_webhook_path,
                params: { discord_webhook_url: "" }
        }.not_to change { NotificationDeliveryChannel.where(kind: "discord").count }
      end

      it "preserves an existing URL and flags on a blank submission" do
        NotificationDeliveryChannel.create!(
          kind: "discord", webhook_url: valid_url,
          everything: true, daily_digest: true
        )
        patch settings_discord_webhook_path,
              params: { discord_webhook_url: "" }
        record = NotificationDeliveryChannel.find_by(kind: "discord")
        expect(record.webhook_url).to eq(valid_url)
        expect(record.everything).to be(true)
        expect(record.daily_digest).to be(true)
      end

      it "redirects with the `unchanged` flash" do
        patch settings_discord_webhook_path,
              params: { discord_webhook_url: "" }
        expect(response).to redirect_to(settings_path)
        expect(flash[:notice]).to match(/Discord unchanged/i)
      end

      it "does not fire a test ping on a blank submission" do
        stub = stub_request(:post, %r{discord(?:app)?\.com})
        patch settings_discord_webhook_path,
              params: { discord_webhook_url: "" }
        expect(stub).not_to have_been_requested
      end

      it "treats a whitespace-only URL as a no-op (strips to blank)" do
        patch settings_discord_webhook_path,
              params: { discord_webhook_url: "   " }
        expect(NotificationDeliveryChannel.where(kind: "discord").count).to eq(0)
        expect(flash[:notice]).to match(/Discord unchanged/i)
      end
    end

    # 2026-05-16 webhook-clear UX tweak.
    # The literal word "clear" (case-insensitive) is the
    # cooperating gesture for the clear-the-integration path: the
    # row persists with `webhook_url = nil` and BOTH routing flags
    # reset to false in the same save. The controller skips the
    # URL-regex check + test ping and routes to the dedicated
    # `persist_cleared_record` path so the operator always sees the
    # same `[cleared]` confirmation regardless of which surface
    # fired the clear.
    context "with the literal `clear` keyword — clear-the-integration gesture" do
      it "creates a row with nil URL and both flags false on a fresh clear" do
        expect {
          patch settings_discord_webhook_path,
                params: { discord_webhook_url: "clear" }
        }.to change { NotificationDeliveryChannel.where(kind: "discord").count }.by(1)
        record = NotificationDeliveryChannel.find_by(kind: "discord")
        expect(record.webhook_url).to be_nil
        expect(record.everything).to be(false)
        expect(record.daily_digest).to be(false)
      end

      it "blanks an existing URL and zeroes both flags on a clear" do
        NotificationDeliveryChannel.create!(
          kind: "discord", webhook_url: valid_url,
          everything: true, daily_digest: true
        )
        patch settings_discord_webhook_path,
              params: { discord_webhook_url: "clear" }
        record = NotificationDeliveryChannel.find_by(kind: "discord")
        expect(record.webhook_url).to be_nil
        expect(record.everything).to be(false)
        expect(record.daily_digest).to be(false)
      end

      it "redirects with the `cleared` flash (distinct from `updated`)" do
        patch settings_discord_webhook_path,
              params: { discord_webhook_url: "clear" }
        expect(response).to redirect_to(settings_path)
        expect(flash[:notice]).to match(/Discord cleared/i)
        expect(flash[:notice]).not_to match(/updated/i)
      end

      it "does not fire a test ping on the clear path" do
        stub = stub_request(:post, %r{discord(?:app)?\.com})
        patch settings_discord_webhook_path,
              params: { discord_webhook_url: "clear" }
        expect(stub).not_to have_been_requested
      end

      it "accepts case-insensitive `CLEAR`" do
        patch settings_discord_webhook_path,
              params: { discord_webhook_url: "CLEAR" }
        record = NotificationDeliveryChannel.find_by(kind: "discord")
        expect(record).to be_present
        expect(record.webhook_url).to be_nil
        expect(flash[:notice]).to match(/Discord cleared/i)
      end
    end

    context "with an invalid URL" do
      it "redirects with an alert and does not save" do
        expect {
          patch settings_discord_webhook_path,
                params: { discord_webhook_url: "https://discord.com/foo" }
        }.not_to change { NotificationDeliveryChannel.count }

        expect(response).to redirect_to(settings_path)
        expect(flash[:alert]).to match(/invalid Discord URL/i)
      end

      it "does not fire a test ping" do
        stub = stub_request(:post, %r{discord(?:app)?\.com})
        patch settings_discord_webhook_path,
              params: { discord_webhook_url: "https://discord.com/foo" }
        expect(stub).not_to have_been_requested
      end

      it "rejects a non-HTTPS URL" do
        bad = "http://discord.com/api/webhooks/123456789012345678/abc-DEF_xyz123"
        patch settings_discord_webhook_path, params: { discord_webhook_url: bad }
        expect(flash[:alert]).to be_present
        expect(NotificationDeliveryChannel.count).to eq(0)
      end

      it "rejects a URL on the wrong host" do
        bad = "https://attacker.com/api/webhooks/123456789012345678/abc-DEF_xyz123"
        patch settings_discord_webhook_path, params: { discord_webhook_url: bad }
        expect(flash[:alert]).to be_present
        expect(NotificationDeliveryChannel.count).to eq(0)
      end

      it "rejects a URL with a non-numeric snowflake ID" do
        bad = "https://discord.com/api/webhooks/notanumber/abc-DEF_xyz123"
        patch settings_discord_webhook_path, params: { discord_webhook_url: bad }
        expect(flash[:alert]).to be_present
        expect(NotificationDeliveryChannel.count).to eq(0)
      end

      it "rejects a URL missing the /api/webhooks/ segment" do
        bad = "https://discord.com/webhooks/123456789012345678/abc-DEF_xyz123"
        patch settings_discord_webhook_path, params: { discord_webhook_url: bad }
        expect(flash[:alert]).to be_present
        expect(NotificationDeliveryChannel.count).to eq(0)
      end

      it "rejects a URL with a trailing query string" do
        bad = valid_url + "?wait=true"
        patch settings_discord_webhook_path, params: { discord_webhook_url: bad }
        expect(flash[:alert]).to be_present
        expect(NotificationDeliveryChannel.count).to eq(0)
      end

      it "rejects a URL with internal whitespace" do
        bad = valid_url + " extra"
        patch settings_discord_webhook_path, params: { discord_webhook_url: bad }
        expect(flash[:alert]).to be_present
        expect(NotificationDeliveryChannel.count).to eq(0)
      end

      it "preserves the previously-saved URL on a bad submission" do
        existing = NotificationDeliveryChannel.create!(
          kind: "discord", webhook_url: valid_url,
          everything: false, daily_digest: false
        )
        patch settings_discord_webhook_path,
              params: { discord_webhook_url: "https://discord.com/foo" }
        expect(existing.reload.webhook_url).to eq(valid_url)
      end
    end

    context "with a valid URL but a failing test ping" do
      it "does not save the row on a 404 response" do
        stub_request(:post, valid_url).to_return(status: 404, body: "")
        expect {
          patch settings_discord_webhook_path,
                params: { discord_webhook_url: valid_url }
        }.not_to change { NotificationDeliveryChannel.count }
        expect(flash[:alert]).to match(/Discord ping failed/i)
      end

      it "does not save the row on a 401 response" do
        stub_request(:post, valid_url).to_return(status: 401, body: "")
        patch settings_discord_webhook_path, params: { discord_webhook_url: valid_url }
        expect(NotificationDeliveryChannel.count).to eq(0)
        expect(flash[:alert]).to match(/Discord ping failed/i)
      end

      it "does not save the row on a 500 response" do
        stub_request(:post, valid_url).to_return(status: 500, body: "")
        patch settings_discord_webhook_path, params: { discord_webhook_url: valid_url }
        expect(NotificationDeliveryChannel.count).to eq(0)
        expect(flash[:alert]).to match(/Discord ping failed/i)
      end

      it "does not save the row on a timeout" do
        stub_request(:post, valid_url).to_raise(::Net::OpenTimeout)
        patch settings_discord_webhook_path, params: { discord_webhook_url: valid_url }
        expect(NotificationDeliveryChannel.count).to eq(0)
        expect(flash[:alert]).to match(/Discord ping failed/i)
      end

      it "does not save the row on a DNS failure" do
        stub_request(:post, valid_url).to_raise(SocketError.new("nope"))
        patch settings_discord_webhook_path, params: { discord_webhook_url: valid_url }
        expect(NotificationDeliveryChannel.count).to eq(0)
        expect(flash[:alert]).to match(/Discord ping failed/i)
      end

      it "preserves the previously-saved row" do
        existing = NotificationDeliveryChannel.create!(
          kind: "discord", webhook_url: valid_url,
          everything: true, daily_digest: true
        )
        new_url = "https://discord.com/api/webhooks/999999999999999999/zZyYxXwW-_1234567"
        stub_request(:post, new_url).to_return(status: 500, body: "")
        patch settings_discord_webhook_path, params: { discord_webhook_url: new_url }
        expect(existing.reload.webhook_url).to eq(valid_url)
        expect(existing.reload.everything).to be(true)
      end
    end
  end

  describe "unauthenticated", :unauthenticated do
    it "bounces to /login without touching anything" do
      stub_request(:post, %r{discord(?:app)?\.com}) # safety — should never fire.
      expect {
        patch settings_discord_webhook_path,
              params: { discord_webhook_url: valid_url }
      }.not_to change { NotificationDeliveryChannel.count }
      expect(response).to redirect_to(login_path)
    end
  end

  describe "friendly URL" do
    it "preserves /settings/discord_webhook" do
      expect(settings_discord_webhook_path).to eq("/settings/discord_webhook")
    end
  end

  # 2026-05-17 form restructure — the URL form no longer reads
  # `everything` / `daily_digest`. The flags moved to the per-flag
  # auto-save endpoint at
  # `PATCH /settings/notification_toggles/discord/<kind>` with
  # `enabled=yes|no`. These yes/no boundary checks exercise the new
  # endpoint so the yes/no contract still has Discord-side coverage in
  # this spec.
  describe "yes/no boundary on `everything` (via NotificationTogglesController)" do
    before do
      stub_request(:post, valid_url).to_return(status: 204, body: "")
      # The toggle requires a configured webhook URL — flipping a flag
      # ON with a blank URL fails the `flags_require_webhook_url`
      # validator.
      patch settings_discord_webhook_path, params: { discord_webhook_url: valid_url }
    end

    it "'yes' → true" do
      patch settings_notification_toggle_path(brand: "discord", kind: "everything"),
            params: { enabled: "yes" }
      expect(NotificationDeliveryChannel.discord.everything).to be(true)
    end

    it "'no' → false" do
      patch settings_notification_toggle_path(brand: "discord", kind: "everything"),
            params: { enabled: "no" }
      expect(NotificationDeliveryChannel.discord.everything).to be(false)
    end

    it "absent → false" do
      patch settings_notification_toggle_path(brand: "discord", kind: "everything")
      expect(NotificationDeliveryChannel.discord.everything).to be(false)
    end
  end

  describe "yes/no boundary on `daily_digest` (via NotificationTogglesController)" do
    before do
      stub_request(:post, valid_url).to_return(status: 204, body: "")
      patch settings_discord_webhook_path, params: { discord_webhook_url: valid_url }
    end

    it "'yes' → true" do
      patch settings_notification_toggle_path(brand: "discord", kind: "daily_digest"),
            params: { enabled: "yes" }
      expect(NotificationDeliveryChannel.discord.daily_digest).to be(true)
    end

    it "'no' → false" do
      patch settings_notification_toggle_path(brand: "discord", kind: "daily_digest"),
            params: { enabled: "no" }
      expect(NotificationDeliveryChannel.discord.daily_digest).to be(false)
    end
  end
end
