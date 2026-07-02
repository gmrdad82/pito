# frozen_string_literal: true

require "rails_helper"

# THE 0.9.0 selection invariant: `with`/`without` messages share the same
# cached request set — only the representation differs. Data layers (L0
# primitives, L0.5 cells) are selection-FREE; the selection filters cells at
# render time.
RSpec.describe "analyze with/without selection invariant", type: :service do
  let(:conversation) { Conversation.singleton }
  let!(:channel)     { create(:channel, :on_connection) }
  let!(:video)       { create(:video, channel: channel, youtube_video_id: "sel_vid_1") }

  let(:full_selection) { nil }
  let(:views_only)     { Pito::Analytics::MetricSelection.from_lists([ :views ], []) }

  def pending_payload(selection)
    Pito::MessageBuilder::Analyze::Message.pending(
      role: "system", title: video.title, level: :vid,
      entity_ids: [ video.id ], period: "28d",
      conversation: conversation, selection: selection
    )
  end

  it "stores the FULL role metric set in the marker regardless of selection (fetch-set is selection-free)" do
    keys_without = pending_payload(full_selection)["analyze"]["metric_keys"]
    keys_with    = pending_payload(views_only)["analyze"]["metric_keys"]

    expect(keys_with).to eq(keys_without)
    expect(keys_with).to eq(Pito::Analytics::MetricOrder.for(role: :system, level: :vid).map(&:to_s))
  end

  context "when two analyze runs differ only in selection" do
    # Canned client — every report method counts and returns plausible rows.
    let(:calls) { { count: 0 } }

    before do
      canned = {
        scalars:              { views: 100, likes: 9, dislikes: 1, estimated_minutes_watched: 600,
                                average_view_duration: 60.0, average_view_percentage: 40.0,
                                subscribers_gained: 2, subscribers_lost: 1, comments: 3 },
        scalars_by_video:     [],
        daily:                [ { day: "2026-06-20", views: 10, estimated_minutes_watched: 60,
                                  average_view_duration: 60.0, average_view_percentage: 40.0,
                                  subscribers_gained: 1, subscribers_lost: 0, likes: 1, comments: 0 } ],
        by_country:           [ { country: "US", views: 10 } ],
        by_device:            [ { device_type: "MOBILE", views: 10 } ],
        by_subscribed_status: [ { subscribed_status: "SUBSCRIBED", views: 10 } ],
        demographics:         [ { age_group: "age25-34", gender: "male", viewer_percentage: 60.0 } ],
        retention:            [ { elapsed_video_time_ratio: 0.5, audience_watch_ratio: 0.5,
                                  relative_retention_performance: 0.5 } ]
      }
      counter = calls
      canned.each do |method, rows|
        allow_any_instance_of(::Channel::Youtube::AnalyticsClient).to receive(method) do |*|
          counter[:count] += 1
          rows
        end
      end
    end

    def run_analyze(selection)
      turn = conversation.turns.create!(
        position: Turn.next_position_for(conversation), input_kind: :chat, input_text: "analyze vid"
      )
      event = Event.create_with_position!(
        conversation:, turn:, kind: :system, payload: pending_payload(selection)
      )
      event.payload.dig("analyze", "metric_keys").each do |key|
        AnalyzeMetricJob.perform_now(event.id, key)
      end
      event.reload
    end

    it "answers the second run entirely from cache (0 extra requests) with a DIFFERENT rendered message" do
      first  = run_analyze(full_selection)
      after_first = calls[:count]
      expect(after_first).to be > 0

      second = run_analyze(views_only)

      expect(calls[:count]).to eq(after_first) # zero additional client calls
      expect(second.payload.dig("analyze", "status")).to eq("ready")
      expect(second.payload["body"]).not_to eq(first.payload["body"])
      # The selected message renders FEWER cells — a views-only card is
      # materially smaller than the full role set.
      expect(second.payload["body"].bytesize).to be < first.payload["body"].bytesize / 2
    end
  end
end
