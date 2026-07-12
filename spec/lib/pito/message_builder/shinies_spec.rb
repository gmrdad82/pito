# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Shinies do
  # ── For a game ─────────────────────────────────────────────────────────────────

  describe "called with a Game" do
    let!(:game) { create(:game, title: "Lies of P") }

    it "returns an html payload" do
      payload = described_class.call(game)
      expect(payload["html"]).to be(true)
      expect(payload["body"]).to be_a(String)
    end

    it "includes the intro (a variant from pito.copy.shinies.intro)" do
      # Pin the sampler so the first variant is always selected.
      Pito::Copy.sampler = ->(entries) { entries.first }
      payload = described_class.call(game)
      expect(payload["body"]).to include("Lies of P")
    ensure
      Pito::Copy.reset_sampler!
    end

    it "wraps the name subject in a pito-subject-shimmer span" do
      payload = described_class.call(game)
      expect(payload["body"]).to match(%r{<span class="pito-subject-shimmer[^"]*">Lies of P</span>})
    end

    it "escapes HTML-special characters in the entity title (no XSS)" do
      game.update!(title: "<b>x</b>")
      payload = described_class.call(game)
      expect(payload["body"]).to include("&lt;b&gt;x&lt;/b&gt;")
      expect(payload["body"]).not_to include("<b>x</b>")
    end

    it "stamps game_id in the payload" do
      payload = described_class.call(game)
      expect(payload["game_id"]).to eq(game.id)
    end

    it "is NOT followupable (no reply handle, no reply target)" do
      payload = described_class.call(game)
      expect(Pito::FollowUp.followupable?(payload)).to be(false)
      expect(payload["reply_handle"]).to be_nil
      expect(payload["reply_target"]).to be_nil
    end

    it "renders one row per metric that has obtained shinies (hiding the rest)" do
      Pito::Achievements::Evaluate.call(achievable: game, metric: "views", value: 100)
      Pito::Achievements::Evaluate.call(achievable: game, metric: "likes", value: 10)
      payload = described_class.call(game)
      expect(payload["body"].scan("pito-achievement-metric-row flex").size).to eq(2)
      expect(payload["body"]).to include("pito-shiny-rail")
    end

    it "hides every metric (no row, no track) when nothing has been earned" do
      payload = described_class.call(game)
      expect(payload["body"]).not_to include("pito-achievement-metric-row")
      expect(payload["body"]).not_to include("pito-shiny-rail")
    end

    context "when the game has obtained achievements" do
      before do
        Pito::Achievements::Evaluate.call(achievable: game, metric: "views", value: 10)
        Pito::Achievements::Evaluate.call(achievable: game, metric: "views", value: 100)
      end

      it "renders badges in timestamp order for the metric" do
        payload = described_class.call(game)
        expect(payload["body"]).to include("pito-shiny")
      end

      it "badge unlock date has no middot separator (block row needs no separator)" do
        payload = described_class.call(game)
        # The .pito-shiny__date span must not start with ·
        expect(payload["body"]).not_to match(%r{class="pito-shiny__date[^"]*">\s*·})
      end
    end

    context "when no achievements are obtained" do
      it "renders zero badge divs" do
        payload = described_class.call(game)
        expect(payload["body"]).not_to include("pito-shiny")
      end
    end
  end

  # ── For a Video ────────────────────────────────────────────────────────────────

  describe "called with a Video" do
    let!(:channel) { create(:channel, handle: "@pito", title: "Pito Channel") }
    let!(:video)   { create(:video, channel:, title: "Boss Rush") }

    it "stamps video_id in the payload" do
      payload = described_class.call(video)
      expect(payload["video_id"]).to eq(video.id)
    end

    it "renders only the metrics that have obtained shinies" do
      Pito::Achievements::Evaluate.call(achievable: video, metric: "views", value: 100)
      payload = described_class.call(video)
      expect(payload["body"].scan("pito-achievement-metric-row flex").size).to eq(1)
    end
  end

  # ── For a Channel ──────────────────────────────────────────────────────────────

  describe "called with a Channel" do
    let!(:channel) { create(:channel, handle: "@pito", title: "Pito Channel") }

    it "stamps channel_id in the payload" do
      payload = described_class.call(channel)
      expect(payload["channel_id"]).to eq(channel.id)
    end

    it "renders only the metrics that have obtained shinies" do
      Pito::Achievements::Evaluate.call(achievable: channel, metric: "subs", value: 100)
      payload = described_class.call(channel)
      expect(payload["body"].scan("pito-achievement-metric-row flex").size).to eq(1)
    end
  end
end
