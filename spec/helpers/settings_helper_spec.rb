require "rails_helper"

# 2026-05-18 (Wave F consolidation) — covers every public method of
# `app/helpers/settings_helper.rb`. Today that is `#webhook_url_mask`,
# the canonical source for the placeholder mask string rendered by the
# Discord / Slack webhook URL inputs in `/settings`.
#
# The mask is the third leg of the secrets-in-DOM defense (the other
# two being Active Record Encryption on
# `NotificationDeliveryChannel#webhook_url` and the `:webhook_url`
# parameter filter in `config/initializers/filter_parameter_logging.rb`).
RSpec.describe SettingsHelper, type: :helper do
  describe "#webhook_url_mask" do
    context "happy path" do
      it "returns the Discord mask for :discord" do
        expect(helper.webhook_url_mask(:discord))
          .to eq("https://discord.com/***")
      end

      it "returns the Slack mask for :slack" do
        expect(helper.webhook_url_mask(:slack))
          .to eq("https://hooks.slack.com/***")
      end

      it "uses the publicly-known prefix for each brand" do
        # Brand prefixes here MUST match the prefixes the real webhook
        # URLs carry (Discord's `https://discord.com/api/webhooks/...`
        # collapses to `https://discord.com/`; Slack's
        # `https://hooks.slack.com/services/...` collapses to
        # `https://hooks.slack.com/`). The secret portion is always
        # masked as `***`.
        expect(helper.webhook_url_mask(:discord)).to start_with("https://discord.com/")
        expect(helper.webhook_url_mask(:slack)).to start_with("https://hooks.slack.com/")
        expect(helper.webhook_url_mask(:discord)).to end_with("***")
        expect(helper.webhook_url_mask(:slack)).to end_with("***")
      end
    end

    context "sad path" do
      it "raises ArgumentError for an unknown brand symbol" do
        expect { helper.webhook_url_mask(:teams) }
          .to raise_error(ArgumentError, /unknown brand: :teams/)
      end

      it "raises ArgumentError for a brand passed as a String" do
        # The method discriminates by Symbol via `case/when`. A String
        # `"discord"` is NOT === `:discord`, so it falls through to the
        # else branch. Locking this prevents a silent regression to a
        # `to_sym` shim that would mask typo-bugs in callers.
        expect { helper.webhook_url_mask("discord") }
          .to raise_error(ArgumentError, /unknown brand: "discord"/)
      end

      it "raises ArgumentError for nil" do
        expect { helper.webhook_url_mask(nil) }
          .to raise_error(ArgumentError, /unknown brand: nil/)
      end

      it "includes the inspected value in the error message" do
        expect { helper.webhook_url_mask(:nope) }
          .to raise_error(ArgumentError, /:nope/)
      end
    end

    context "edge cases" do
      it "returns a plain (frozen-literal-equivalent) String, not html_safe" do
        # The mask is used as a `placeholder=""` attribute value. The
        # method returns a plain String literal; Rails escapes
        # placeholder attributes on render. Locking that we don't
        # accidentally start returning `html_safe?` strings (which
        # would skip the auto-escape).
        result = helper.webhook_url_mask(:discord)

        expect(result).to be_a(String)
        expect(result).not_to be_html_safe
      end

      it "returns the same string on repeated calls (stateless)" do
        expect(helper.webhook_url_mask(:discord))
          .to eq(helper.webhook_url_mask(:discord))
        expect(helper.webhook_url_mask(:slack))
          .to eq(helper.webhook_url_mask(:slack))
      end

      it "does not reveal any portion of a real webhook URL beyond the publicly-known prefix" do
        # Defense-in-depth contract: the mask must never include
        # anything that looks like a real Discord webhook id /
        # token (long numeric id + opaque token) or a Slack
        # services path (`T.../B.../...`).
        discord_mask = helper.webhook_url_mask(:discord)
        slack_mask   = helper.webhook_url_mask(:slack)

        expect(discord_mask).not_to match(/\/api\/webhooks\//)
        expect(discord_mask).not_to match(/\d{17,}/)
        expect(slack_mask).not_to match(/\/services\//)
        expect(slack_mask).not_to match(/\bT[A-Z0-9]{8,}\b/)
        expect(slack_mask).not_to match(/\bB[A-Z0-9]{8,}\b/)
      end
    end
  end

  # FB-166 (2026-05-21) — Ruby-declared focusables contract for the
  # notifications pane + stack sub-panels. Each focusable carries a
  # `:style` that maps to one of four CSS focus visuals:
  #
  #   * `:checkbox_label` — tint around the inline-flex label+checkbox
  #   * `:input`          — section-accent border on the input only
  #   * `:action`         — compact tint around the bracketed action
  #   * `:row`            — full-width tint (sessions table rows; see
  #                         Sessions::TableComponent#focusables for
  #                         the `:row` style)
  #
  # Specs lock document order + per-key style so the cursor's j/k
  # cycle has a stable, spec-asserted contract instead of relying on
  # scattered HTML attributes.
  describe "#notifications_focusables (FB-166 — Ruby-driven focus contract)" do
    it "returns the 8 focusables in locked document order" do
      expect(helper.notifications_focusables.map { |f| f[:key] }).to eq([
        "all",
        "daily",
        "discord_webhook",
        "discord_update",
        "discord_help",
        "slack_webhook",
        "slack_update",
        "slack_help"
      ])
    end

    it "stamps :checkbox_label on the two shared toggles (all + daily)" do
      by_key = helper.notifications_focusables.index_by { |f| f[:key] }
      expect(by_key["all"][:style]).to eq(:checkbox_label)
      expect(by_key["daily"][:style]).to eq(:checkbox_label)
    end

    it "stamps :input on the two webhook URL inputs" do
      by_key = helper.notifications_focusables.index_by { |f| f[:key] }
      expect(by_key["discord_webhook"][:style]).to eq(:input)
      expect(by_key["slack_webhook"][:style]).to eq(:input)
    end

    it "stamps :action on the four bracketed [update] / [help] actions" do
      by_key = helper.notifications_focusables.index_by { |f| f[:key] }
      expect(by_key["discord_update"][:style]).to eq(:action)
      expect(by_key["discord_help"][:style]).to eq(:action)
      expect(by_key["slack_update"][:style]).to eq(:action)
      expect(by_key["slack_help"][:style]).to eq(:action)
    end
  end

  describe "#stack_reindex_focusables (FB-166 — Ruby-driven focus contract)" do
    it "returns a single :action focusable when the reindex job is idle" do
      result = helper.stack_reindex_focusables(running: false)
      expect(result).to eq([ { key: "reindex", style: :action } ])
    end

    it "returns an empty list while the reindex is running (no focus stop)" do
      expect(helper.stack_reindex_focusables(running: true)).to eq([])
    end
  end
end
