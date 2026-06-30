# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::ScopeResolver do
  subject(:result) { described_class.call(raw:, channel_scope:) }

  let(:channel_scope) { "@all" }

  describe "bare `analyze` (no entity)" do
    let(:raw) { "analyze" }

    it "suggests options and does nothing" do
      expect(result).to be_suggest
      expect(result.level).to be_nil
      expect(result.scopes).to be_empty
    end

    it "also suggests for a bare alias (`stats`)" do
      expect(described_class.call(raw: "stats", channel_scope:)).to be_suggest
    end

    # No-guess parity (owner 2026-06-29): analyze NEVER defaults to game. An
    # unknown entity word or a bare id resolves to :suggest (show options), never
    # a silent game analysis — the else branch is :suggest, not a game guess.
    it "an unknown entity word (`analyze foobar`) → suggest, never a game" do
      r = described_class.call(raw: "analyze foobar", channel_scope:)
      expect(r).to be_suggest
      expect(r.level).to be_nil
    end

    it "a bare id (`analyze 123`) → suggest, never a game" do
      r = described_class.call(raw: "analyze 123", channel_scope:)
      expect(r).to be_suggest
      expect(r.level).to be_nil
    end
  end

  describe "analyze channel — bare (6a)" do
    let(:raw) { "analyze channel" }

    context "when shift+tab is @all" do
      let!(:channels) { create_list(:channel, 2) }

      it "resolves to all channels at :channel level" do
        expect(result).to be_ok
        expect(result.level).to eq(:channel)
        expect(result.scopes).to match_array(channels)
      end
    end

    context "when shift+tab is a specific channel" do
      let(:channel_scope) { "@gmrdad82" }
      let!(:channel) { create(:channel, handle: "gmrdad82") }
      let!(:other)   { create(:channel, handle: "manfyhard") }

      it "resolves to only that channel (ignoring the others)" do
        expect(result.level).to eq(:channel)
        expect(result.scopes).to eq([ channel ])
      end
    end

    context "when shift+tab names an unknown channel" do
      let(:channel_scope) { "@ghost" }

      it "errors with channel_not_found" do
        expect(result).to be_error
        expect(result.error_key).to eq(:channel_not_found)
        expect(result.error_args).to eq(handle: "@ghost")
      end
    end
  end

  describe "analyze channel/channels @handle (6b/6c)" do
    let!(:a) { create(:channel, handle: "gmrdad82") }
    let!(:b) { create(:channel, handle: "manfyhard") }

    it "resolves a single explicit handle, ignoring shift+tab" do
      res = described_class.call(raw: "analyze channel @gmrdad82", channel_scope: "@all")
      expect(res.level).to eq(:channel)
      expect(res.scopes).to eq([ a ])
    end

    it "resolves multiple explicit handles" do
      res = described_class.call(raw: "analyze channels @gmrdad82, @manfyhard", channel_scope: "@all")
      expect(res.scopes).to match_array([ a, b ])
    end

    it "errors listing unknown handles" do
      res = described_class.call(raw: "analyze channels @gmrdad82, @nope", channel_scope: "@all")
      expect(res).to be_error
      expect(res.error_key).to eq(:channels_not_found)
      expect(res.error_args[:handles]).to include("@nope")
    end
  end

  describe "analyze vids (6d / 6e)" do
    context "bare `analyze vids` → reduces to channel (6d)" do
      let(:raw) { "analyze vids" }
      let!(:channels) { create_list(:channel, 2) }

      it "is interpreted as analyze channel at :channel level" do
        expect(result.level).to eq(:channel)
        expect(result.scopes).to match_array(channels)
      end
    end

    context "with explicit ids (6e)" do
      let!(:v1) { create(:video) }
      let!(:v2) { create(:video) }

      it "resolves those vids at :vid level, ignoring shift+tab" do
        res = described_class.call(raw: "analyze vids ##{v1.id}, ##{v2.id}", channel_scope: "@all")
        expect(res.level).to eq(:vid)
        expect(res.scopes).to match_array([ v1, v2 ])
      end

      it "errors listing unknown ids" do
        res = described_class.call(raw: "analyze vids ##{v1.id}, #999999", channel_scope: "@all")
        expect(res).to be_error
        expect(res.error_key).to eq(:vids_not_found)
        expect(res.error_args[:ids]).to include("#999999")
      end
    end
  end

  describe "analyze games (6f / 6f-bis)" do
    context "with explicit ids (6f)" do
      let!(:g1) { create(:game) }
      let!(:g2) { create(:game) }

      it "resolves those games at :game level" do
        res = described_class.call(raw: "analyze games ##{g1.id}, ##{g2.id}", channel_scope: "@all")
        expect(res.level).to eq(:game)
        expect(res.scopes).to match_array([ g1, g2 ])
      end

      it "errors listing unknown ids" do
        res = described_class.call(raw: "analyze games #888888", channel_scope: "@all")
        expect(res).to be_error
        expect(res.error_key).to eq(:games_not_found)
      end
    end

    context "bare `analyze games` → shift+tab channels → their linked games (6f-bis)" do
      let(:channel)   { create(:channel, handle: "gmrdad82") }
      let(:other_ch)  { create(:channel, handle: "manfyhard") }
      let(:on_video)  { create(:video, channel:) }
      let(:off_video) { create(:video, channel: other_ch) }
      let!(:linked)   { create(:game).tap { |g| create(:video_game_link, video: on_video, game: g) } }
      let!(:elsewhere) { create(:game).tap { |g| create(:video_game_link, video: off_video, game: g) } }

      it "returns only games linked to the scoped channel's videos" do
        res = described_class.call(raw: "analyze games", channel_scope: "@gmrdad82")
        expect(res.level).to eq(:game)
        expect(res.scopes).to eq([ linked ])
        expect(res.scopes).not_to include(elsewhere)
      end

      it "with @all returns every linked game" do
        res = described_class.call(raw: "analyze games", channel_scope: "@all")
        expect(res.scopes).to match_array([ linked, elsewhere ])
      end
    end
  end

  describe "noun synonyms" do
    let!(:v) { create(:video) }

    it "accepts singular `vid` and `video`" do
      [ "analyze vid ##{v.id}", "analyze video ##{v.id}" ].each do |raw|
        expect(described_class.call(raw:, channel_scope: "@all").scopes).to eq([ v ])
      end
    end
  end
end
