# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Analytics::Enhanced do
  let(:channel) { create(:channel) }
  let(:video)   { create(:video, channel: channel, title: "Boss Fight Highlights") }
  let(:game)    { create(:game, title: "Lies of P") }

  # Deterministic first-variant sampler is installed globally by spec/support/copy.rb.

  describe ".pending?" do
    it "returns true when the event payload has analytics.status == 'pending'" do
      event = instance_double("Event", payload: { "analytics" => { "status" => "pending" } })
      expect(described_class.pending?(event)).to be(true)
    end

    it "returns false when the event payload has analytics.status == 'ready'" do
      event = instance_double("Event", payload: { "analytics" => { "status" => "ready" } })
      expect(described_class.pending?(event)).to be(false)
    end

    it "returns false when the payload has no analytics key" do
      event = instance_double("Event", payload: { "text" => "hello" })
      expect(described_class.pending?(event)).to be(false)
    end

    it "returns false when the payload is not a Hash" do
      event = instance_double("Event", payload: nil)
      expect(described_class.pending?(event)).to be(false)
    end

    it "returns true for a real pending payload built by .pending" do
      payload = described_class.pending(game, period: "28d")
      event = instance_double("Event", payload: payload)
      expect(described_class.pending?(event)).to be(true)
    end

    it "returns false for a real ready payload built by .ready_payload" do
      intro   = "some intro"
      payload = described_class.ready_payload(scope: game, period: "28d", result: :unavailable, intro: intro)
      event = instance_double("Event", payload: payload)
      expect(described_class.pending?(event)).to be(false)
    end
  end

  describe ".pending" do
    context "with a game scope" do
      subject(:payload) { described_class.pending(game, period: "28d") }

      it "sets html: true" do
        expect(payload["html"]).to be(true)
      end

      it "sets anchor: true so the segment gets a replaceable event_<id> DOM id" do
        expect(payload["anchor"]).to be(true)
      end

      it "sets analytics.status to 'pending'" do
        expect(payload.dig("analytics", "status")).to eq("pending")
      end

      it "sets analytics.scope_type to the scope class name" do
        expect(payload.dig("analytics", "scope_type")).to eq("Game")
      end

      it "sets analytics.scope_id to the scope id" do
        expect(payload.dig("analytics", "scope_id")).to eq(game.id)
      end

      it "forces analytics.period to 'lifetime' regardless of the period arg" do
        expect(payload.dig("analytics", "period")).to eq("lifetime")
      end

      it "stores a non-blank intro in the analytics marker" do
        expect(payload.dig("analytics", "intro")).to be_a(String).and(be_present)
      end

      it "intro in the marker includes the scope title" do
        expect(payload.dig("analytics", "intro")).to include("Lies of P")
      end

      it "body includes the intro text (HTML-encoded)" do
        intro = payload.dig("analytics", "intro")
        expect(payload["body"]).to include(ERB::Util.html_escape(intro))
      end

      it "wraps the title subject in a pito-subject-shimmer span" do
        expect(payload["body"]).to match(%r{<span class="pito-subject-shimmer[^"]*">Lies of P</span>})
        # The stored marker intro is itself the html_safe shimmer string.
        expect(payload.dig("analytics", "intro")).to include("pito-subject-shimmer")
      end

      it "escapes HTML-special characters in the scope title (no XSS)" do
        game.update!(title: "<b>x</b>")
        expect(payload["body"]).to include("&lt;b&gt;x&lt;/b&gt;")
        expect(payload["body"]).not_to include("<b>x</b>")
      end

      it "body includes data-pito-ts-slot" do
        expect(payload["body"]).to include("data-pito-ts-slot")
      end

      it "body INCLUDES the scalars table in loading state" do
        expect(payload["body"]).to include("pito-analytics-scalars")
      end

      it "marker stores a token (8-char hex string)" do
        expect(payload.dig("analytics", "token")).to match(/\A[0-9a-f]{8}\z/)
      end

      it "marker stores metric_keys with the 5 glance metric keys in order" do
        expect(payload.dig("analytics", "metric_keys")).to eq(
          %w[views watched_hours avg_view_duration subs_net likes]
        )
      end

      it "body does NOT include the unavailable note marker" do
        expect(payload["body"]).not_to include("pito-analytics-enhanced__note")
      end
    end

    context "with a video scope" do
      subject(:payload) { described_class.pending(video, period: "7d") }

      it "sets analytics.scope_type to 'Video'" do
        expect(payload.dig("analytics", "scope_type")).to eq("Video")
      end

      it "sets analytics.scope_id to the video id" do
        expect(payload.dig("analytics", "scope_id")).to eq(video.id)
      end

      it "intro includes the video title" do
        expect(payload.dig("analytics", "intro")).to include("Boss Fight Highlights")
      end
    end

    context "with period nil" do
      it "still forces the analytics marker period to 'lifetime'" do
        payload = described_class.pending(game)
        expect(payload.dig("analytics", "period")).to eq("lifetime")
      end
    end
  end

  describe ".ready_payload" do
    let(:metrics) do
      {
        views:             { current: 1234, previous: 1000 },
        watched_hours:     { current: 12.5, previous: 10.0 },
        avg_view_duration: { current: 245,  previous: 200 },
        avg_viewed_pct:    { current: 38.2, previous: 40.0 },
        subs_gained:       { current: 20,   previous: 10 },
        subs_lost:         { current: 9,    previous: 4 },
        likes:             { current: 210,  previous: 180 },
        dislikes:          { current: 4,    previous: 2 },
        comments:          { current: 31,   previous: 30 }
      }
    end
    let(:result)  { Pito::Analytics::Scalars::Result.new(metrics: metrics, label: "28d", comparable: true) }
    let(:intro)   { "Lies of P, by the numbers." }

    subject(:payload) { described_class.ready_payload(scope: game, period: "28d", result: result, intro: intro) }

    it "sets html: true" do
      expect(payload["html"]).to be(true)
    end

    it "sets analytics.status to 'ready'" do
      expect(payload.dig("analytics", "status")).to eq("ready")
    end

    it "sets analytics.scope_type" do
      expect(payload.dig("analytics", "scope_type")).to eq("Game")
    end

    it "sets analytics.scope_id" do
      expect(payload.dig("analytics", "scope_id")).to eq(game.id)
    end

    it "reuses the intro verbatim in the analytics marker" do
      expect(payload.dig("analytics", "intro")).to eq(intro)
    end

    it "body includes the intro text" do
      expect(payload["body"]).to include(intro)
    end

    it "body includes data-pito-ts-slot" do
      expect(payload["body"]).to include("data-pito-ts-slot")
    end

    it "body includes the scalars table marker" do
      expect(payload["body"]).to include("pito-analytics-scalars")
    end

    it "body does NOT include the unavailable note" do
      expect(payload["body"]).not_to include("pito-analytics-enhanced__note")
    end

    context "when result is :unavailable" do
      subject(:payload) { described_class.ready_payload(scope: game, period: "28d", result: :unavailable, intro: intro) }

      it "sets analytics.status to 'ready'" do
        expect(payload.dig("analytics", "status")).to eq("ready")
      end

      it "reuses the intro verbatim" do
        expect(payload.dig("analytics", "intro")).to eq(intro)
      end

      it "body includes the unavailable note" do
        expect(payload["body"]).to include("pito-analytics-enhanced__note")
      end

      it "body does NOT include the scalars table" do
        expect(payload["body"]).not_to include("pito-analytics-scalars")
      end
    end

    context "channel scope (Phase 4)" do
      subject(:payload) { described_class.ready_payload(scope: channel, period: "28d", result: result, intro: intro) }

      it "sets analytics.scope_type to 'Channel'" do
        expect(payload.dig("analytics", "scope_type")).to eq("Channel")
      end

      it "renders the channel-specific 'use analyze' nudge after the panel" do
        node  = Nokogiri::HTML.fragment(payload["body"])
        nudge = node.css(".pito-analytics-enhanced__nudge")
        expect(nudge).not_to be_empty
        expect(nudge.text).to include("analyze channel")
      end
    end
  end

  # Multi-id at-a-glance: `.pending` accepts a SET of same-level records and emits
  # one combined pending glance whose marker carries scope_ids for the fill.
  describe ".pending over a set (combined glance)" do
    let(:video2) { create(:video, channel: channel, title: "Boss Fight Encore") }

    subject(:payload) { described_class.pending([ video, video2 ], period: "lifetime") }

    it "stores scope_ids (not a single scope_id) in the marker" do
      expect(payload.dig("analytics", "scope_ids")).to eq([ video.id, video2.id ])
      expect(payload.dig("analytics", "scope_id")).to be_nil
    end

    it "keeps scope_type as the member class" do
      expect(payload.dig("analytics", "scope_type")).to eq("Video")
    end

    it "titles the intro as 'N vids'" do
      expect(payload["body"]).to include("2 vids")
    end

    it "is still a pending glance the fill job recognises" do
      event = build_stubbed(:event, payload:)
      expect(described_class.pending?(event)).to be(true)
    end
  end
end
