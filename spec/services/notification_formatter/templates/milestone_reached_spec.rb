require "rails_helper"

RSpec.describe NotificationFormatter::Templates::MilestoneReached do
  let(:cal_entry) { create(:calendar_entry) }
  let(:payload) do
    {
      "rule_id"              => 1,
      "rule_name"            => "10k subs",
      "metric"               => "subscribers",
      "threshold"            => 10_000,
      "metric_value_at_fire" => 10_042,
      "scope_type"           => "install",
      "scope_id"             => nil,
      "scope_label"          => "this install"
    }
  end
  let(:notification) do
    create(:notification, :milestone_reached,
           event_payload: payload,
           source_calendar_entry: cal_entry)
  end
  let(:template) { described_class.new(notification) }

  describe "#title" do
    it "is `milestone: <rule_name>`" do
      expect(template.title).to eq("milestone: 10k subs")
    end
  end

  describe "#body" do
    it "carries metric, threshold, value, and scope" do
      expect(template.body).to eq(
        "subscribers crossed 10000 at 10042 on this install."
      )
    end

    it "uses scope_label when present" do
      n = create(:notification, :milestone_reached,
                 event_payload: payload.merge("scope_label" => "Bake Lab"),
                 source_calendar_entry: cal_entry)
      expect(described_class.new(n).body).to include("on Bake Lab.")
    end

    it "uses `this install` when scope_type is install and scope_label missing" do
      n = create(:notification, :milestone_reached,
                 event_payload: payload.except("scope_label"),
                 source_calendar_entry: cal_entry)
      expect(described_class.new(n).body).to include("on this install.")
    end

    it "falls back to a placeholder for channel scope without scope_label" do
      n = create(:notification, :milestone_reached,
                 event_payload: payload.merge("scope_type" => "channel").except("scope_label"),
                 source_calendar_entry: cal_entry)
      expect(described_class.new(n).body).to include("(channel unavailable)")
    end
  end

  describe "#url" do
    it "is /calendar/entries/<source_calendar_entry_id>" do
      expect(template.url).to eq("/calendar/entries/#{cal_entry.id}")
    end

    it "is nil when no source_calendar_entry" do
      n = create(:notification, :milestone_reached,
                 event_payload: payload,
                 with_calendar_entry: false,
                 dedup_key: "milestone-1")
      expect(described_class.new(n).url).to be_nil
    end
  end

  it "is graceful with empty event_payload" do
    n = build(:notification, :milestone_reached, event_payload: {})
    n.save!
    t = described_class.new(n)
    expect { t.title }.not_to raise_error
    expect { t.body }.not_to raise_error
    expect { t.url }.not_to raise_error
  end
end
