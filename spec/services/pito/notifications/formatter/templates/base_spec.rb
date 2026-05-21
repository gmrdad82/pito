require "rails_helper"

RSpec.describe Pito::Notifications::Formatter::Templates::Base do
  let(:notification) { build_stubbed(:notification, with_calendar_entry: false, dedup_key: "base-spec") }
  let(:template) { described_class.new(notification) }

  it "stashes the notification" do
    expect(template.notification).to eq(notification)
  end

  it "raises NotImplementedError on #title" do
    expect { template.title }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError on #body" do
    expect { template.body }.to raise_error(NotImplementedError)
  end

  it "raises NotImplementedError on #url" do
    expect { template.url }.to raise_error(NotImplementedError)
  end

  describe "#payload (private)" do
    it "returns the event_payload as HashWithIndifferentAccess" do
      n = build_stubbed(:notification, with_calendar_entry: false, dedup_key: "p1", event_payload: { "video_title" => "demo" })
      t = described_class.new(n)
      payload = t.send(:payload)
      expect(payload[:video_title]).to eq("demo")
      expect(payload["video_title"]).to eq("demo")
    end

    it "returns an empty hash for a nil payload (defensive)" do
      # The DB enforces NOT NULL on event_payload, but the formatter
      # should still degrade gracefully if some pathway hands it a row
      # whose `event_payload` reads nil (e.g., a stub / partial double).
      n = build_stubbed(:notification, with_calendar_entry: false, dedup_key: "p2")
      allow(n).to receive(:event_payload).and_return(nil)
      t = described_class.new(n)
      expect(t.send(:payload)).to be_empty
    end
  end

  describe "#fetch (private)" do
    it "returns the value when present" do
      n = build_stubbed(:notification, with_calendar_entry: false, dedup_key: "f1", event_payload: { "video_title" => "demo" })
      t = described_class.new(n)
      expect(t.send(:fetch, :video_title)).to eq("demo")
    end

    it "returns the fallback when missing" do
      n = build_stubbed(:notification, with_calendar_entry: false, dedup_key: "f2", event_payload: {})
      t = described_class.new(n)
      expect(t.send(:fetch, :video_title, "fallback")).to eq("fallback")
    end

    it "returns nil by default for missing keys" do
      n = build_stubbed(:notification, with_calendar_entry: false, dedup_key: "f3", event_payload: {})
      t = described_class.new(n)
      expect(t.send(:fetch, :missing)).to be_nil
    end
  end

  describe "#join_list (private)" do
    it "joins arrays with commas" do
      t = described_class.new(notification)
      expect(t.send(:join_list, %w[a b c])).to eq("a, b, c")
    end

    it "returns the fallback for nil" do
      t = described_class.new(notification)
      expect(t.send(:join_list, nil, fallback: "tbd")).to eq("tbd")
    end

    it "returns the fallback for empty arrays" do
      t = described_class.new(notification)
      expect(t.send(:join_list, [], fallback: "tbd")).to eq("tbd")
    end

    it "drops blank entries" do
      t = described_class.new(notification)
      expect(t.send(:join_list, [ "a", nil, "", "b" ])).to eq("a, b")
    end
  end
end
