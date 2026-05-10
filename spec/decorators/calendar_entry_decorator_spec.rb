require "rails_helper"

# Phase 21 — JSON Endpoints for CLI / MCP Parity. The decorator owns
# the JSON wire shape for calendar entries (summary + detail).
RSpec.describe CalendarEntryDecorator do
  let(:entry) do
    create(
      :calendar_entry,
      entry_type: :custom,
      title: "manual entry",
      starts_at: Time.zone.parse("2026-05-13T17:00:00Z"),
      ends_at: nil,
      all_day: false,
      timezone: "Europe/Bucharest",
      state: :scheduled,
      source: :manual
    )
  end
  let(:decorator) { described_class.new(entry) }

  describe "#as_summary_json" do
    let(:json) { decorator.as_summary_json }

    it "carries the row-level keys" do
      expect(json.keys).to match_array(
        %i[id entry_type title starts_at ends_at all_day timezone state
           source read_only game_id video_id channel_id project_id
           milestone_rule_id]
      )
    end

    it "serializes all_day as yes/no" do
      expect(json[:all_day]).to eq("no")

      entry.update!(all_day: true)
      expect(described_class.new(entry.reload).as_summary_json[:all_day]).to eq("yes")
    end

    it "serializes timestamps as ISO-8601" do
      expect(json[:starts_at]).to start_with("2026-05-13T17:00:00")
    end

    it "renders ends_at null when absent" do
      expect(json[:ends_at]).to be_nil
    end

    it "serializes read_only as yes/no (manual entries: 'no')" do
      expect(json[:read_only]).to eq("no")
    end

    it "serializes read_only as yes for derived entries" do
      derived = create(:calendar_entry, :video_published)
      expect(described_class.new(derived).as_summary_json[:read_only]).to eq("yes")
    end
  end

  describe "#as_detail_json" do
    let(:json) { decorator.as_detail_json }

    it "includes every summary key" do
      expect(json).to include(*decorator.as_summary_json.keys)
    end

    it "adds the detail-only fields" do
      expect(json).to include(
        :description, :manual_date_override, :release_precision,
        :tba_remind_monthly, :notify_anyway, :metadata,
        :parent_entry_id, :child_entry_ids, :created_by_user_id,
        :created_at, :updated_at
      )
    end

    it "serializes manual_date_override / tba_remind_monthly / notify_anyway as yes/no" do
      expect(json[:manual_date_override]).to eq("no")
      expect(json[:tba_remind_monthly]).to eq("no")
      expect(json[:notify_anyway]).to eq("no")
    end

    it "renders child_entry_ids as a list" do
      # Use a game_release parent (purchase_planned needs a parent
      # entry, and game_release supports child purchase_planned).
      parent = create(
        :calendar_entry,
        entry_type: :game_release,
        source: :derived,
        title: "released: x",
        starts_at: 1.day.from_now,
        source_ref: { "game_id" => 42 }
      )
      child = create(
        :calendar_entry,
        entry_type: :purchase_planned,
        parent_entry: parent,
        starts_at: 1.day.from_now,
        timezone: "Europe/Bucharest"
      )
      expect(described_class.new(parent.reload).as_detail_json[:child_entry_ids]).to include(child.id)
    end

    it "renders metadata as {} when empty hash" do
      entry.update_column(:metadata, {})
      detail = described_class.new(entry.reload).as_detail_json
      expect(detail[:metadata]).to eq({})
    end

    it "does NOT include dispatch_declarations on the entry hash" do
      # `dispatch_declarations` is a top-level sibling in the view; the
      # decorator surfaces it via a separate accessor.
      expect(json).not_to have_key(:dispatch_declarations)
    end
  end

  describe "#dispatch_declarations_json" do
    it "returns a list with ISO-8601 fires_at" do
      release = create(
        :calendar_entry,
        entry_type: :game_release,
        source: :derived,
        starts_at: Time.zone.parse("2026-05-13T17:00:00Z"),
        release_precision: :day,
        title: "release",
        source_ref: { "game_id" => 1 }
      )
      decls = described_class.new(release).dispatch_declarations_json
      expect(decls).to be_an(Array)
      decls.each do |d|
        expect(d[:fires_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
        expect(d).to have_key(:kind)
        expect(d).to have_key(:severity)
      end
    end

    it "returns [] for entry_types without declarations" do
      expect(decorator.dispatch_declarations_json).to eq([])
    end
  end
end
