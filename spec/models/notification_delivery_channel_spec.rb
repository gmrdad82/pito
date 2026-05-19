require "rails_helper"

# Phase 26 — 01b. Install-level webhook configuration storage. The AR
# model holds the per-provider webhook URL + routing flags. Validation
# guards a) the `kind` enum, b) the singleton-per-kind unique index,
# c) the URL shape via per-kind regex.
RSpec.describe NotificationDeliveryChannel, type: :model do
  let(:valid_slack_url) { "https://hooks.slack.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567" }
  let(:valid_discord_url) { "https://discord.com/api/webhooks/123456789012345678/abc-DEF_xyz123" }

  describe "schema" do
    it "carries the expected columns" do
      expect(described_class.column_names).to include(
        "id", "kind", "webhook_url", "everything", "daily_digest",
        "last_validated_at", "created_at", "updated_at"
      )
    end

    it "defaults `everything` to false" do
      record = described_class.new(kind: "slack", webhook_url: valid_slack_url)
      expect(record.everything).to be(false)
    end

    it "defaults `daily_digest` to false" do
      record = described_class.new(kind: "slack", webhook_url: valid_slack_url)
      expect(record.daily_digest).to be(false)
    end
  end

  describe "validations" do
    it "requires `kind`" do
      record = described_class.new(kind: nil, webhook_url: valid_slack_url)
      expect(record).not_to be_valid
      expect(record.errors[:kind]).to be_present
    end

    it "rejects unknown `kind` values" do
      record = described_class.new(kind: "email", webhook_url: "https://example.test/x")
      expect(record).not_to be_valid
      expect(record.errors[:kind]).to be_present
    end

    it "accepts `slack` kind" do
      record = described_class.new(kind: "slack", webhook_url: valid_slack_url)
      expect(record).to be_valid
    end

    it "accepts `discord` kind" do
      record = described_class.new(kind: "discord", webhook_url: valid_discord_url)
      expect(record).to be_valid
    end

    it "enforces uniqueness on `kind`" do
      described_class.create!(kind: "slack", webhook_url: valid_slack_url)
      dup = described_class.new(kind: "slack", webhook_url: valid_slack_url)
      expect(dup).not_to be_valid
      expect(dup.errors[:kind]).to be_present
    end

    # 2026-05-16 webhook-clear UX tweak.
    # `webhook_url` is nullable now — a nil URL is the "integration
    # cleared" state. The `before_validation` callback that powers the
    # invariant is exercised in its own block below.
    it "accepts a nil `webhook_url`" do
      record = described_class.new(kind: "slack", webhook_url: nil)
      expect(record).to be_valid
    end

    it "accepts an empty `webhook_url` (normalized to nil before validation)" do
      record = described_class.new(kind: "slack", webhook_url: "")
      expect(record).to be_valid
      expect(record.webhook_url).to be_nil
    end

    it "rejects a Slack webhook URL that does not match the regex" do
      record = described_class.new(kind: "slack", webhook_url: "https://hooks.slack.com/foo")
      expect(record).not_to be_valid
      # 2026-05-17 — the kind-specific error copy reads "is not a valid
      # Slack webhook URL." (brand label is the proper-noun spelling
      # via `BRAND_LABELS`). The previous lowercase assertion no longer
      # matches.
      expect(record.errors[:webhook_url].first).to include("Slack")
    end

    it "rejects an http (non-TLS) Slack URL" do
      bad = valid_slack_url.sub("https://", "http://")
      record = described_class.new(kind: "slack", webhook_url: bad)
      expect(record).not_to be_valid
    end

    it "rejects a Slack URL on the wrong host" do
      bad = "https://attacker.com/services/T01ABCD/B02EFGH/abcdefXYZ1234567"
      record = described_class.new(kind: "slack", webhook_url: bad)
      expect(record).not_to be_valid
    end

    it "rejects a Discord URL where Slack is the declared kind" do
      record = described_class.new(kind: "slack", webhook_url: valid_discord_url)
      expect(record).not_to be_valid
    end

    it "accepts a Discord URL with the discordapp.com legacy host" do
      url = valid_discord_url.sub("discord.com", "discordapp.com")
      record = described_class.new(kind: "discord", webhook_url: url)
      expect(record).to be_valid
    end
  end

  # 2026-05-16 webhook-clear UX tweak.
  # The model carries the invariant "URL nil implies both flags false"
  # via a `before_validation` callback. The blocks below pin the
  # callback's behavior across every entry point (web form,
  # MCP tool, console). Two complementary surfaces:
  #
  #   * The callback itself NORMALIZES — blank URL → nil, both flags
  #     drop to false on the same save.
  #   * The `flags_require_webhook_url` validator REJECTS the
  #     contradictory shape (flag true + URL nil) as defense in depth
  #     for any code path that bypasses the callback.
  describe "before_validation — clear-on-blank invariant" do
    it "normalizes a blank `webhook_url` to nil on save" do
      record = described_class.new(kind: "slack", webhook_url: "")
      record.valid?
      expect(record.webhook_url).to be_nil
    end

    it "normalizes a whitespace-only `webhook_url` to nil on save" do
      record = described_class.new(kind: "slack", webhook_url: "   ")
      record.valid?
      expect(record.webhook_url).to be_nil
    end

    it "strips surrounding whitespace from a present `webhook_url`" do
      padded = "  #{valid_slack_url}  "
      record = described_class.new(kind: "slack", webhook_url: padded)
      record.valid?
      expect(record.webhook_url).to eq(valid_slack_url)
    end

    it "zeroes `everything` when `webhook_url` is blanked" do
      record = described_class.create!(
        kind: "slack", webhook_url: valid_slack_url, everything: true
      )
      record.update!(webhook_url: "")
      expect(record.everything).to be(false)
      expect(record.webhook_url).to be_nil
    end

    it "zeroes `daily_digest` when `webhook_url` is blanked" do
      record = described_class.create!(
        kind: "slack", webhook_url: valid_slack_url, daily_digest: true
      )
      record.update!(webhook_url: "")
      expect(record.daily_digest).to be(false)
    end

    it "zeroes BOTH flags in the same save when the URL is blanked" do
      record = described_class.create!(
        kind: "slack", webhook_url: valid_slack_url,
        everything: true, daily_digest: true
      )
      record.update!(webhook_url: "")
      expect(record.everything).to be(false)
      expect(record.daily_digest).to be(false)
    end

    it "leaves flags untouched when the URL is present" do
      record = described_class.new(
        kind: "slack", webhook_url: valid_slack_url,
        everything: true, daily_digest: true
      )
      record.valid?
      expect(record.everything).to be(true)
      expect(record.daily_digest).to be(true)
    end

    it "does not mutate flags when the model is loaded with both flags false" do
      record = described_class.create!(kind: "slack", webhook_url: nil)
      expect(record.everything).to be(false)
      expect(record.daily_digest).to be(false)
    end
  end

  describe "flags_require_webhook_url validator" do
    # 2026-05-17 — the original combined `nilify_blank_webhook_url_and_zero_flags`
    # `before_validation` callback was split (see model header): the
    # flag-zeroing half moved to `before_save` so the validator sees the
    # user-submitted intent (flag-on with blank URL) and fails LOUDLY
    # instead of silently no-opping after the callback already coerced
    # the flag to false. The validator is now the primary user-facing
    # gate; the `before_save` callback is defense-in-depth.
    it "rejects `everything: true` with a nil URL (form-tampered combination)" do
      record = described_class.new(kind: "slack", webhook_url: nil, everything: true)
      expect(record).not_to be_valid
      expect(record.errors[:base].join).to match(/Slack webhook URL not configured/i)
      # The post-validation `before_save` flag-zeroing callback only
      # fires inside `save` — `valid?` alone leaves the flag at the
      # caller-submitted value so the validator can see it.
      expect(record.everything).to be(true)
    end

    it "rejects `daily_digest: true` with a nil URL" do
      record = described_class.new(kind: "slack", webhook_url: nil, daily_digest: true)
      expect(record).not_to be_valid
      # Kind-specific copy — proper-noun brand label via `BRAND_LABELS`.
      expect(record.errors[:base].join).to match(/Slack webhook URL not configured/i)
    end

    it "accepts both flags true with a present URL" do
      record = described_class.new(
        kind: "slack", webhook_url: valid_slack_url,
        everything: true, daily_digest: true
      )
      expect(record).to be_valid
    end

    it "accepts both flags false with a nil URL" do
      record = described_class.new(kind: "slack", webhook_url: nil)
      expect(record).to be_valid
    end
  end

  describe "#valid_url?" do
    it "returns true for a regex-matching Slack URL" do
      record = described_class.new(kind: "slack", webhook_url: valid_slack_url)
      expect(record.valid_url?).to be(true)
    end

    it "returns false for a regex-mismatching Slack URL" do
      record = described_class.new(kind: "slack", webhook_url: "https://hooks.slack.com/foo")
      expect(record.valid_url?).to be(false)
    end

    it "returns false when `webhook_url` is blank" do
      record = described_class.new(kind: "slack", webhook_url: "")
      expect(record.valid_url?).to be(false)
    end

    it "returns false for an unknown kind" do
      record = described_class.new(kind: "email", webhook_url: valid_slack_url)
      expect(record.valid_url?).to be(false)
    end
  end

  describe ".for_kind" do
    it "scopes to the requested kind" do
      slack = described_class.create!(kind: "slack", webhook_url: valid_slack_url)
      discord = described_class.create!(kind: "discord", webhook_url: valid_discord_url)
      expect(described_class.for_kind("slack")).to contain_exactly(slack)
      expect(described_class.for_kind("discord")).to contain_exactly(discord)
    end

    it "accepts a symbol" do
      slack = described_class.create!(kind: "slack", webhook_url: valid_slack_url)
      expect(described_class.for_kind(:slack)).to contain_exactly(slack)
    end
  end

  describe ".find_record_for" do
    it "returns the single AR row for a kind" do
      record = described_class.create!(kind: "slack", webhook_url: valid_slack_url)
      expect(described_class.find_record_for("slack")).to eq(record)
    end

    it "returns nil when no row exists for the kind" do
      expect(described_class.find_record_for("slack")).to be_nil
    end
  end

  describe ".slack / .discord shorthands" do
    it ".slack returns the slack row" do
      record = described_class.create!(kind: "slack", webhook_url: valid_slack_url)
      expect(described_class.slack).to eq(record)
    end

    it ".discord returns the discord row" do
      record = described_class.create!(kind: "discord", webhook_url: valid_discord_url)
      expect(described_class.discord).to eq(record)
    end

    it ".slack returns nil when no slack row exists" do
      expect(described_class.slack).to be_nil
    end
  end

  describe ".for(kind) — dispatcher entry point" do
    # Phase 26 01b refactor — `NotificationDeliveryChannel.for(kind)`
    # MUST keep returning a PORO dispatcher (not an AR row) so the
    # existing job code (`NotificationDeliver`) and existing service
    # specs continue to work. The AR row lookup moved to
    # `.find_record_for`.
    it "returns a Slack PORO dispatcher for 'slack'" do
      expect(described_class.for("slack")).to be_a(NotificationDeliveryChannel::Slack)
    end

    it "returns a Discord PORO dispatcher for 'discord'" do
      expect(described_class.for("discord")).to be_a(NotificationDeliveryChannel::Discord)
    end

    it "returns an InApp PORO dispatcher for 'in_app'" do
      expect(described_class.for("in_app")).to be_a(NotificationDeliveryChannel::InApp)
    end

    it "raises on an unknown kind" do
      expect { described_class.for("email") }.to raise_error(ArgumentError, /unknown channel/)
    end
  end

  describe "Active Record Encryption on `webhook_url`" do
    # Sanity check that the URL persists round-trip even though
    # `encrypts :webhook_url` is in play — the ciphertext is opaque
    # to the test harness but the model layer decrypts on read.
    it "round-trips a Slack URL through encrypted storage" do
      described_class.create!(kind: "slack", webhook_url: valid_slack_url)
      record = described_class.find_by(kind: "slack")
      expect(record.webhook_url).to eq(valid_slack_url)
    end

    it "stores the ciphertext (not plaintext) in the underlying column" do
      described_class.create!(kind: "slack", webhook_url: valid_slack_url)
      # `Connection#select_value` reaches under ARE so we see the raw
      # ciphertext. The plaintext URL must NOT appear in the storage
      # blob.
      raw = described_class.connection.select_value(
        "SELECT webhook_url FROM notification_delivery_channels WHERE kind = 'slack'"
      )
      expect(raw).not_to include("hooks.slack.com")
    end

    # Phase 29 — Unit A1. `encrypts :webhook_url` is PROBABILISTIC (no
    # `deterministic: true`) — the same plaintext under two rows must
    # produce different ciphertext. This is the encryption-mechanism
    # regression check Unit A1's acceptance list calls for.
    it "encrypts probabilistically — two rows with the same URL differ in ciphertext" do
      # Two `slack` rows can't coexist (unique index on `kind`), so use
      # the two kinds and bypass the per-kind URL-shape validation
      # (irrelevant to the encryption mechanism under test).
      described_class.create!(kind: "slack", webhook_url: valid_slack_url)
      discord_row = described_class.new(kind: "discord", webhook_url: valid_slack_url)
      discord_row.save!(validate: false)
      raw_slack = described_class.connection.select_value(
        "SELECT webhook_url FROM notification_delivery_channels WHERE kind = 'slack'"
      )
      raw_discord = described_class.connection.select_value(
        "SELECT webhook_url FROM notification_delivery_channels WHERE kind = 'discord'"
      )
      expect(raw_slack).not_to eq(raw_discord)
      # Both still decrypt back to the same plaintext.
      expect(described_class.find_by(kind: "slack").webhook_url).to eq(valid_slack_url)
      expect(described_class.find_by(kind: "discord").webhook_url).to eq(valid_slack_url)
    end
  end
end
