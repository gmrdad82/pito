require "rails_helper"

RSpec.describe NotificationFormatter::Templates::VideoPublished do
  let(:payload) do
    {
      "video_id"      => 42,
      "video_title"   => "How to bake bread",
      "channel_id"    => 7,
      "channel_title" => "Bake Lab",
      "published_at"  => "2026-05-10T10:00:00Z",
      "watch_url"     => "https://youtube.com/watch?v=abc"
    }
  end
  let(:notification) do
    build_stubbed(:notification, :video_published, with_calendar_entry: false, dedup_key: "vp-base", event_payload: payload)
  end
  let(:template) { described_class.new(notification) }

  describe "#title" do
    it "is `published: <video_title>`" do
      expect(template.title).to eq("published: How to bake bread")
    end

    it "uses a placeholder when video_title is missing" do
      n = build_stubbed(:notification, :video_published, with_calendar_entry: false, dedup_key: "vp1", event_payload: {})
      expect(described_class.new(n).title).to include("(video title unavailable)")
    end
  end

  describe "#body" do
    it "mentions the channel and the video and links to youtube" do
      body = template.body
      expect(body).to include("Bake Lab")
      expect(body).to include("How to bake bread")
      expect(body).to include("[watch on youtube](https://youtube.com/watch?v=abc)")
    end

    it "omits the watch link when watch_url is missing" do
      n = build_stubbed(:notification, :video_published, with_calendar_entry: false, dedup_key: "vp2", event_payload: payload.except("watch_url"))
      expect(described_class.new(n).body).not_to include("[watch on youtube]")
    end
  end

  describe "#url" do
    it "is /videos/<video_id>" do
      expect(template.url).to eq("/videos/42")
    end

    it "is nil when video_id is missing" do
      n = build_stubbed(:notification, :video_published, with_calendar_entry: false, dedup_key: "vp3", event_payload: payload.except("video_id"))
      expect(described_class.new(n).url).to be_nil
    end
  end

  it "reads ONLY from event_payload" do
    # Stubbing the source row to nil — the template still works because
    # all rendering data lives in event_payload.
    allow(notification).to receive(:source_calendar_entry).and_return(nil)
    expect(template.title).to include("How to bake bread")
    expect(template.body).to include("Bake Lab")
  end

  it "preserves Unicode in titles" do
    n = build_stubbed(:notification, :video_published, with_calendar_entry: false, dedup_key: "vp4",
               event_payload: payload.merge("video_title" => "日本語 ✨ تجربة"))
    expect(described_class.new(n).title).to include("日本語 ✨ تجربة")
  end

  it "is graceful with empty event_payload" do
    n = build(:notification, :video_published, event_payload: {})
    n.save!
    t = described_class.new(n)
    expect { t.title }.not_to raise_error
    expect { t.body }.not_to raise_error
    expect { t.url }.not_to raise_error
  end
end
