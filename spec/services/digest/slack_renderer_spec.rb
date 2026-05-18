require "rails_helper"

# Phase 26 — 01e. Slack Block Kit renderer.
RSpec.describe ::Digest::SlackRenderer do
  let(:user) { build_stubbed(:user, time_zone: "Europe/Bucharest") }
  let(:now) { Time.utc(2026, 6, 15, 12, 0, 0) }

  def build_result(sections: {})
    ::Digest::Composer::Result.new(
      user: user,
      window_started_at: now - 24.hours,
      window_ended_at: now,
      channels_synced: build_section(sections.fetch(:channels_synced, [])),
      videos_imported: build_section(sections.fetch(:videos_imported, []), label: "videos imported"),
      videos_updated: build_section(sections.fetch(:videos_updated, []), label: "videos updated"),
      footage_imported: build_section(sections.fetch(:footage_imported, []), label: "footage imported"),
      notifications_open: build_section(sections.fetch(:notifications_open, []), label: "open notifications")
    )
  end

  def build_section(items, label: "channels synced", total: nil)
    ::Digest::Composer::Section.new(
      label: label,
      total: total || items.size,
      items: items
    )
  end

  describe "envelope" do
    it "returns a hash with `text` fallback and `blocks` array" do
      payload = described_class.new(build_result).call
      expect(payload).to have_key("text")
      expect(payload["blocks"]).to be_an(Array)
    end

    it "includes a header block" do
      payload = described_class.new(build_result).call
      header = payload["blocks"].find { |b| b["type"] == "header" }
      expect(header).to be_present
      expect(header.dig("text", "text")).to eq("pito daily digest")
    end

    it "includes a context block carrying the rendered window range" do
      payload = described_class.new(build_result).call
      context = payload["blocks"].find { |b| b["type"] == "context" }
      expect(context).to be_present
      txt = context["elements"].first["text"]
      # Bucharest is UTC+3 in June (EEST). 12:00 UTC → 15:00 local.
      expect(txt).to include("15:00")
    end
  end

  describe "with activity" do
    let(:result) do
      build_result(sections: {
        channels_synced: [ "channel A", "channel B" ],
        videos_imported: [ "video 1" ]
      })
    end

    it "emits one section block per non-empty section" do
      payload = described_class.new(result).call
      section_blocks = payload["blocks"].select { |b| b["type"] == "section" }
      expect(section_blocks.size).to eq(2)
    end

    it "uses mrkdwn text with a bold label" do
      payload = described_class.new(result).call
      section_block = payload["blocks"].find do |b|
        b["type"] == "section" && b.dig("text", "text").to_s.include?("channels synced")
      end
      expect(section_block).to be_present
      expect(section_block.dig("text", "type")).to eq("mrkdwn")
      expect(section_block.dig("text", "text")).to include("*channels synced*")
    end

    it "bullets every item" do
      payload = described_class.new(result).call
      section_block = payload["blocks"].find do |b|
        b["type"] == "section" && b.dig("text", "text").to_s.include?("channels synced")
      end
      txt = section_block.dig("text", "text")
      expect(txt).to include("• channel A")
      expect(txt).to include("• channel B")
    end

    it "appends `… and N more` when item list is shorter than the total" do
      sec = build_section([ "a", "b" ], label: "channels synced", total: 12)
      result = build_result.tap { |r| r.channels_synced = sec }
      payload = described_class.new(result).call
      section_block = payload["blocks"].find do |b|
        b["type"] == "section" && b.dig("text", "text").to_s.include?("channels synced")
      end
      expect(section_block.dig("text", "text")).to include("… and 10 more")
    end

    it "inserts divider blocks between sections" do
      payload = described_class.new(result).call
      dividers = payload["blocks"].select { |b| b["type"] == "divider" }
      expect(dividers).to be_present
    end

    it "suppresses empty sections entirely" do
      payload = described_class.new(result).call
      json = payload.to_json
      expect(json).not_to include("login attempts")
    end

    it "produces a meaningful `text` fallback" do
      payload = described_class.new(result).call
      expect(payload["text"]).to include("pito daily digest")
      expect(payload["text"]).to include("2 channels synced")
    end
  end

  describe "all-quiet fallback" do
    it "renders a one-line `no activity` section block" do
      payload = described_class.new(build_result).call
      json = payload["blocks"].to_json
      expect(json).to include("no activity in the last 24 hours")
    end

    it "uses an all-quiet `text` fallback" do
      payload = described_class.new(build_result).call
      expect(payload["text"]).to include("no activity")
    end
  end

  describe "tz-aware window rendering (Pacific/Kiritimati UTC+14)" do
    let(:user) { build_stubbed(:user, time_zone: "Pacific/Kiritimati") }

    it "renders the window end in the user's local zone" do
      payload = described_class.new(build_result).call
      context = payload["blocks"].find { |b| b["type"] == "context" }
      txt = context["elements"].first["text"]
      # 2026-06-15 12:00 UTC → 2026-06-16 02:00 LINT.
      expect(txt).to include("02:00")
    end
  end

  describe "tz-aware window rendering (Pacific/Pago_Pago UTC-11)" do
    let(:user) { build_stubbed(:user, time_zone: "Pacific/Pago_Pago") }

    it "renders the window end in the user's local zone" do
      payload = described_class.new(build_result).call
      context = payload["blocks"].find { |b| b["type"] == "context" }
      txt = context["elements"].first["text"]
      # 2026-06-15 12:00 UTC → 2026-06-15 01:00 SST (UTC-11).
      expect(txt).to include("01:00")
    end
  end
end
