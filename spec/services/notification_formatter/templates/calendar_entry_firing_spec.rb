require "rails_helper"

RSpec.describe NotificationFormatter::Templates::CalendarEntryFiring do
  let(:cal_entry) { create(:calendar_entry) }
  let(:payload) do
    {
      "entry_id"    => cal_entry.id,
      "entry_type"  => "custom",
      "title"       => "Stream prep",
      "description" => "Lighting check + mic levels",
      "starts_at"   => "2026-05-10T15:00:00Z"
    }
  end
  let(:notification) do
    create(:notification, :calendar_entry_firing,
           event_payload: payload,
           source_calendar_entry: cal_entry)
  end
  let(:template) { described_class.new(notification) }

  describe "#title" do
    it "is the calendar entry title verbatim" do
      expect(template.title).to eq("Stream prep")
    end
  end

  describe "#body" do
    it "is the description when non-blank" do
      expect(template.body).to eq("Lighting check + mic levels")
    end

    it "falls back to `calendar entry fired.` when description is blank" do
      n = create(:notification, :calendar_entry_firing,
                 event_payload: payload.merge("description" => ""),
                 source_calendar_entry: cal_entry)
      expect(described_class.new(n).body).to eq("calendar entry fired.")
    end

    it "falls back to `calendar entry fired.` when description is nil" do
      n = create(:notification, :calendar_entry_firing,
                 event_payload: payload.merge("description" => nil),
                 source_calendar_entry: cal_entry)
      expect(described_class.new(n).body).to eq("calendar entry fired.")
    end
  end

  describe "#url" do
    it "is /calendar/entries/<entry_id>" do
      expect(template.url).to eq("/calendar/entries/#{cal_entry.id}")
    end

    it "falls back to source_calendar_entry_id when entry_id is missing" do
      n = create(:notification, :calendar_entry_firing,
                 event_payload: payload.except("entry_id"),
                 source_calendar_entry: cal_entry)
      expect(described_class.new(n).url).to eq("/calendar/entries/#{cal_entry.id}")
    end
  end

  it "is graceful with empty event_payload" do
    n = build(:notification, :calendar_entry_firing, event_payload: {})
    n.save!
    t = described_class.new(n)
    expect { t.title }.not_to raise_error
    expect { t.body }.not_to raise_error
    expect { t.url }.not_to raise_error
  end
end
