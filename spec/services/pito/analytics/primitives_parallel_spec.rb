# frozen_string_literal: true

require "rails_helper"

# NON-transactional: the parallel path's worker threads write through their own
# pooled connections, which a per-example transaction cannot see or roll back.
# Every row this group creates is cleaned explicitly.
RSpec.describe Pito::Analytics::Primitives, "parallel cold fetches" do
  self.use_transactional_tests = false

  let(:reference_date) { Date.new(2026, 1, 15) }
  let(:window)         { Pito::Analytics::Window.for("7d", reference_date: reference_date) }
  let!(:channel)       { create(:channel, :on_connection) }
  let(:vid_ids)        { %w[par_vid_1 par_vid_2 par_vid_3 par_vid_4 par_vid_5 par_vid_6] }

  before { described_class.max_concurrency = 4 }

  after do
    described_class.max_concurrency = 1
    AnalyticsPrimitive.where(video_youtube_id: vid_ids).delete_all
    channel.youtube_connection&.destroy
    channel.destroy
  end

  it "fetches every cold subject concurrently and stores one row each" do
    seen = []
    mutex = Mutex.new
    allow_any_instance_of(::Channel::Youtube::AnalyticsClient).to receive(:daily) do |_, videos:, **|
      mutex.synchronize { seen << [ Thread.current.object_id, videos ] }
      [ { day: "2026-01-10", views: 5 } ]
    end

    result = described_class.fetch(
      groups: [ [ channel, vid_ids ] ], window:, report: "daily", now: Time.current
    )

    expect(result.keys).to match_array(vid_ids)
    expect(result.values).to all(eq([ { "day" => "2026-01-10", "views" => 5 } ]))
    expect(AnalyticsPrimitive.where(video_youtube_id: vid_ids, report: "daily").count).to eq(6)
    expect(seen.map(&:first).uniq.size).to be > 1 # ran on more than one thread
  end

  it "re-raises the first fetch error after joining (sequential semantics preserved)" do
    allow_any_instance_of(::Channel::Youtube::AnalyticsClient)
      .to receive(:daily).and_raise(RuntimeError, "API down")

    expect {
      described_class.fetch(groups: [ [ channel, vid_ids ] ], window:, report: "daily", now: Time.current)
    }.to raise_error(RuntimeError, "API down")
  end

  # G131: a per-subject Channel::Youtube error is ISOLATED in the pool — the
  # surviving subjects' rows still come back, the fetch does not raise, and the
  # failing subject writes no row (stays cold, can recover).
  it "isolates a per-subject YouTube error and returns the survivors' rows" do
    bad = vid_ids.first
    allow_any_instance_of(::Channel::Youtube::AnalyticsClient).to receive(:daily) do |_, videos:, **|
      raise ::Channel::Youtube::TransientError, "5xx" if videos == [ bad ]

      [ { day: "2026-01-10", views: 7 } ]
    end

    result = nil
    expect {
      result = described_class.fetch(groups: [ [ channel, vid_ids ] ], window:, report: "daily", now: Time.current)
    }.not_to raise_error

    (vid_ids - [ bad ]).each { |vid| expect(result[vid]).to eq([ { "day" => "2026-01-10", "views" => 7 } ]) }
    expect(result[bad]).to eq([])
    expect(AnalyticsPrimitive.where(video_youtube_id: bad, report: "daily")).to be_empty
  end

  it "never spawns threads for warm subjects" do
    vid_ids.each do |vid|
      create(:analytics_primitive, video_youtube_id: vid, report: "daily",
             start_date: window.start_date, end_date: window.end_date,
             period_token: "7d", metrics: [ { "day" => "2026-01-10", "views" => 1 } ],
             expires_at: 1.hour.from_now)
    end
    allow(::Channel::Youtube::AnalyticsClient).to receive(:new)

    result = described_class.fetch(
      groups: [ [ channel, vid_ids ] ], window:, report: "daily", now: Time.current
    )

    expect(result.keys).to match_array(vid_ids)
    expect(::Channel::Youtube::AnalyticsClient).not_to have_received(:new)
  end
end
