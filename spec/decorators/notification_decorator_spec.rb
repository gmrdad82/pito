require "rails_helper"

# Phase 21 — JSON Endpoints for CLI / MCP Parity. The decorator owns
# the JSON wire shape for notifications (summary + detail).
RSpec.describe NotificationDecorator do
  let(:notification) do
    create(
      :notification,
      kind: :video_published,
      event_type: "video_published",
      severity: :info,
      title: "video published",
      body: "the video is live.",
      url: "/videos/abc123",
      fires_at: Time.zone.parse("2026-05-10T17:00:00Z"),
      retry_count: 0,
      last_error: nil
    )
  end
  let(:decorator) { described_class.new(notification) }

  describe "#as_summary_json" do
    let(:json) { decorator.as_summary_json }

    it "carries the row-level keys" do
      expect(json.keys).to match_array(
        %i[id kind severity event_type title body url fires_at
           in_app_read_at read discord_delivered_at slack_delivered_at
           retry_count last_error created_at]
      )
    end

    it "serializes read as yes/no" do
      expect(json[:read]).to eq("no")

      notification.update!(in_app_read_at: Time.current)
      expect(described_class.new(notification.reload).as_summary_json[:read]).to eq("yes")
    end

    it "serializes timestamps as ISO-8601" do
      expect(json[:fires_at]).to start_with("2026-05-10T17:00:00")
      expect(json[:created_at]).to match(/\A\d{4}-\d{2}-\d{2}T/)
    end

    it "renders in_app_read_at null when unread" do
      expect(json[:in_app_read_at]).to be_nil
    end

    it "renders delivery timestamps null when undelivered" do
      expect(json[:discord_delivered_at]).to be_nil
      expect(json[:slack_delivered_at]).to be_nil
    end
  end

  describe "#as_detail_json" do
    let(:json) { decorator.as_detail_json }

    it "returns a { notification:, payload: } hash" do
      expect(json.keys).to match_array(%i[notification payload])
    end

    it "wraps the summary under :notification" do
      expect(json[:notification]).to eq(decorator.as_summary_json)
    end

    it "wraps the formatter output under :payload" do
      expect(json[:payload]).to be_a(Hash)
      expect(json[:payload]).to have_key(:title)
      expect(json[:payload]).to have_key(:severity)
    end
  end
end
