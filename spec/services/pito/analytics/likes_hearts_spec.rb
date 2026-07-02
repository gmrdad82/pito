# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::LikesHearts do
  # A stub AnalyticsClient whose #scalars returns a fixed likes/dislikes row,
  # keyed by whether a `videos:` filter was passed. Since 0.9.0 the ratio folds
  # from the primitives layer, which fetches one row PER SUBJECT (per video) —
  # `scoped` is therefore the PER-VIDEO row, summed across the scope's vids.
  def stub_client(scoped:, channel_wide:)
    client = instance_double(::Channel::Youtube::AnalyticsClient)
    allow(::Channel::Youtube::AnalyticsClient).to receive(:new).and_return(client)
    allow(client).to receive(:scalars) do |videos: nil, **|
      videos ? scoped : channel_wide
    end
    # Multi-vid groups batch through the Top-videos report (Phase 3): one row
    # per filtered video, each carrying the per-video `scoped` metrics.
    allow(client).to receive(:scalars_by_video) do |videos:, **|
      videos.map { |id| scoped.merge(video: id) }
    end
  end

  let(:connection) { instance_double("conn", needs_reauth: false) }
  let(:channel) do
    instance_double(::Channel, id: 1, youtube_channel_id: "UC1", youtube_connection: connection)
  end
  let(:groups) { [ [ channel, [ "vid1", "vid2" ] ] ] }

  it "returns subject (red) + channel (purple) hearts for vid level" do
    stub_client(scoped: { likes: 90, dislikes: 10 }, channel_wide: { likes: 880, dislikes: 120 })

    hearts = described_class.for(groups:, level: "vid")

    expect(hearts.size).to eq(2)
    # Two vids × the per-video row (90/10) — subjects sum.
    expect(hearts[0]).to include(color: :red,    likes: 180, dislikes: 20, score: 90.0)
    expect(hearts[1]).to include(color: :purple, likes: 880, dislikes: 120, score: 88.0)
  end

  it "folds from warm primitives with zero client calls" do
    lifetime = Pito::Analytics::Window.for("lifetime", reference_date: Date.current)
    { "vid1" => { "likes" => 90, "dislikes" => 10 },
      "vid2" => { "likes" => 30, "dislikes" => 10 },
      "UC1"  => { "likes" => 880, "dislikes" => 120 } }.each do |subject, metrics|
      create(:analytics_primitive, video_youtube_id: subject, report: "scalars",
             start_date: lifetime.start_date, end_date: lifetime.end_date,
             period_token: "lifetime", metrics:, expires_at: 1.hour.from_now)
    end
    allow(::Channel::Youtube::AnalyticsClient).to receive(:new)

    hearts = described_class.for(groups:, level: "vid")

    expect(hearts[0]).to include(likes: 120, dislikes: 20, score: 85.7)
    expect(hearts[1]).to include(likes: 880, dislikes: 120)
    expect(::Channel::Youtube::AnalyticsClient).not_to have_received(:new)
  end

  it "returns a single purple channel heart for channel level" do
    stub_client(scoped: { likes: 5, dislikes: 5 }, channel_wide: { likes: 880, dislikes: 120 })

    hearts = described_class.for(groups: [ [ channel, :channel ] ], level: "channel")

    expect(hearts.size).to eq(1)
    expect(hearts.first).to include(color: :purple, score: 88.0)
  end

  it "computes the score as likes / (likes + dislikes) × 100, rounded to 1 dp" do
    stub_client(scoped: { likes: 2, dislikes: 1 }, channel_wide: { likes: 2, dislikes: 1 })
    hearts = described_class.for(groups:, level: "vid")
    expect(hearts.first[:score]).to eq(66.7)
  end

  it "returns nil when there are no ratings (likes + dislikes == 0)" do
    stub_client(scoped: { likes: 0, dislikes: 0 }, channel_wide: { likes: 0, dislikes: 0 })
    expect(described_class.for(groups:, level: "vid")).to be_nil
  end

  it "returns nil for empty groups" do
    expect(described_class.for(groups: [], level: "vid")).to be_nil
  end

  it "rescues a client error to nil (cell falls back to scaffold)" do
    allow(::Channel::Youtube::AnalyticsClient).to receive(:new).and_raise(StandardError, "boom")
    expect(described_class.for(groups:, level: "vid")).to be_nil
  end
end
