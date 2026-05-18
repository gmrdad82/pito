require "rails_helper"

# Phase 26 — 01e. Discord embeds renderer.
RSpec.describe ::Digest::DiscordRenderer do
  let(:user) { build_stubbed(:user, time_zone: "Europe/Bucharest") }
  let(:now) { Time.utc(2026, 6, 15, 12, 0, 0) }

  def build_result(sections: {})
    ::Digest::Composer::Result.new(
      user: user,
      window_started_at: now - 24.hours,
      window_ended_at: now,
      channels_synced: build_section(sections.fetch(:channels_synced, []), label: "channels synced"),
      videos_imported: build_section(sections.fetch(:videos_imported, []), label: "videos imported"),
      videos_updated: build_section(sections.fetch(:videos_updated, []), label: "videos updated"),
      footage_imported: build_section(sections.fetch(:footage_imported, []), label: "footage imported"),
      notifications_open: build_section(sections.fetch(:notifications_open, []), label: "open notifications")
    )
  end

  def build_section(items, label:, total: nil)
    ::Digest::Composer::Section.new(
      label: label,
      total: total || items.size,
      items: items
    )
  end

  describe "envelope" do
    it "returns a hash with `content` and a single embed" do
      payload = described_class.new(build_result).call
      expect(payload["content"]).to eq("pito daily digest")
      expect(payload["embeds"]).to be_an(Array)
      expect(payload["embeds"].size).to eq(1)
    end

    it "stamps an ISO 8601 timestamp on the embed" do
      payload = described_class.new(build_result).call
      ts = payload["embeds"].first["timestamp"]
      expect { Time.parse(ts) }.not_to raise_error
    end

    it "carries the window range in the embed description" do
      payload = described_class.new(build_result).call
      desc = payload["embeds"].first["description"]
      # Bucharest UTC+3 in June (EEST). 12:00 UTC → 15:00 local.
      expect(desc).to include("15:00")
    end
  end

  describe "with activity" do
    let(:result) do
      build_result(sections: {
        channels_synced: [ "channel A", "channel B" ],
        videos_imported: [ "video 1" ]
      })
    end

    it "emits one field per non-empty section" do
      payload = described_class.new(result).call
      fields = payload["embeds"].first["fields"]
      expect(fields.size).to eq(2)
    end

    it "includes the total in the field name" do
      payload = described_class.new(result).call
      fields = payload["embeds"].first["fields"]
      ch = fields.find { |f| f["name"].start_with?("channels synced") }
      expect(ch["name"]).to eq("channels synced (2)")
    end

    it "bullets every item in the field value" do
      payload = described_class.new(result).call
      fields = payload["embeds"].first["fields"]
      ch = fields.find { |f| f["name"].start_with?("channels synced") }
      expect(ch["value"]).to include("• channel A")
      expect(ch["value"]).to include("• channel B")
    end

    it "appends `… and N more` when total exceeds the item list" do
      sec = build_section([ "a", "b" ], label: "channels synced", total: 12)
      result = build_result.tap { |r| r.channels_synced = sec }
      payload = described_class.new(result).call
      fields = payload["embeds"].first["fields"]
      ch = fields.find { |f| f["name"].start_with?("channels synced") }
      expect(ch["value"]).to include("… and 10 more")
    end

    it "suppresses empty sections entirely" do
      payload = described_class.new(result).call
      fields = payload["embeds"].first["fields"]
      expect(fields.map { |f| f["name"] }).not_to include(/login attempts/)
    end

    it "respects Discord's 1024-char field value limit" do
      huge = Array.new(50) { "x" * 200 }
      sec = build_section(huge, label: "channels synced", total: 50)
      result = build_result.tap { |r| r.channels_synced = sec }
      payload = described_class.new(result).call
      field = payload["embeds"].first["fields"].first
      expect(field["value"].length).to be <= described_class::FIELD_VALUE_MAX
    end
  end

  describe "all-quiet fallback" do
    it "includes a `no activity` line in the description" do
      payload = described_class.new(build_result).call
      desc = payload["embeds"].first["description"]
      expect(desc).to include("no activity in the last 24 hours")
    end

    it "emits no fields when there is no activity" do
      payload = described_class.new(build_result).call
      expect(payload["embeds"].first["fields"]).to be_nil.or eq([])
    end
  end

  describe "tz-aware rendering (Pacific/Kiritimati UTC+14)" do
    let(:user) { build_stubbed(:user, time_zone: "Pacific/Kiritimati") }

    it "renders the window range in the user's local zone" do
      payload = described_class.new(build_result).call
      desc = payload["embeds"].first["description"]
      # 2026-06-15 12:00 UTC → 02:00 next day local on Kiritimati.
      expect(desc).to include("02:00")
    end
  end

  describe "tz-aware rendering (Pacific/Pago_Pago UTC-11)" do
    let(:user) { build_stubbed(:user, time_zone: "Pacific/Pago_Pago") }

    it "renders the window range in the user's local zone" do
      payload = described_class.new(build_result).call
      desc = payload["embeds"].first["description"]
      # 2026-06-15 12:00 UTC → 01:00 same day Pago Pago.
      expect(desc).to include("01:00")
    end
  end
end
