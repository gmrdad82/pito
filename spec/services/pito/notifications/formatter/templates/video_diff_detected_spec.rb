require "rails_helper"

RSpec.describe Pito::Notifications::Formatter::Templates::VideoDiffDetected do
  let(:video) { create(:video, title: "MyVideoTitle") }
  let(:diff) do
    create(:video_diff, video: video, payload: {
      "title"       => { "pito" => "p", "youtube" => "y" },
      "description" => { "pito" => "pd", "youtube" => "yd" }
    })
  end
  let(:payload) do
    {
      "video_id"    => video.id,
      "video_slug"  => video.to_param,
      "video_title" => video.title,
      "diff_id"     => diff.id,
      "fields"      => %w[title description]
    }
  end
  let(:notification) do
    create(:notification,
           kind: :video_diff_detected,
           event_type: "video_diff_detected",
           severity: :info,
           title: "tmp",
           event_payload: payload,
           dedup_key: "video_diff:test:#{rand(1_000_000)}",
           with_calendar_entry: false)
  end
  let(:template) { described_class.new(notification) }

  describe "#title" do
    it "summarises the field count" do
      expect(template.title).to eq("youtube diverged on 2 fields")
    end

    it "uses singular for a one-field diff" do
      notification.update_columns(event_payload: payload.merge("fields" => %w[title]))
      expect(template.title).to eq("youtube diverged on 1 field")
    end
  end

  describe "#body" do
    it "includes the video title and the field list" do
      expect(template.body).to include("MyVideoTitle")
      expect(template.body).to include("title, description")
    end

    it "is graceful with empty event_payload" do
      n = build(:notification,
                kind: :video_diff_detected,
                event_type: "video_diff_detected",
                event_payload: {},
                with_calendar_entry: false,
                dedup_key: "video_diff:empty:#{rand(1_000_000)}")
      n.save!
      t = described_class.new(n)
      expect { t.title }.not_to raise_error
      expect { t.body }.not_to raise_error
      expect { t.url }.not_to raise_error
    end
  end

  describe "#url" do
    it "is /videos/:slug/diff" do
      expect(template.url).to eq("/videos/#{video.to_param}/diff")
    end

    it "returns nil without a slug" do
      notification.update_columns(event_payload: payload.except("video_slug"))
      expect(template.url).to be_nil
    end
  end
end
