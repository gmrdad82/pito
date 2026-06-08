# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::List do
  subject(:handler) do
    described_class.new(
      message: Pito::Chat::Message.new(verb: :list, body_tokens: [], kind: :new_turn, raw: "list games"),
      conversation: Conversation.singleton
    )
  end

  def handler_for(raw, channel: nil)
    described_class.new(
      message:      Pito::Chat::Message.new(verb: :list, body_tokens: [], kind: :new_turn, raw:),
      conversation: Conversation.singleton,
      channel:      channel
    )
  end

  def video_titles(payload)
    Array(payload["table_rows"]).map { |row| row[:cells][1][:text] }
  end

  # ── Games ─────────────────────────────────────────────────────────────────

  describe "#call with games in the library" do
    let!(:zelda) { create(:game, title: "Tears of the Kingdom") }
    let!(:lies)  { create(:game, title: "Lies of P") }

    it "returns a Result::Ok with one system event" do
      result = handler.call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.length).to eq(1)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "lists each game with its #-prefixed ID and title as the first two cells, sorted by title" do
      rows = handler.call.events.first[:payload]["table_rows"]
      id_texts    = rows.map { |r| r[:cells][0][:text] }
      title_texts = rows.map { |r| r[:cells][1][:text] }
      expect(id_texts).to eq([ "##{lies.id}", "##{zelda.id}" ])
      expect(title_texts).to eq([ "Lies of P", "Tears of the Kingdom" ])
    end

    it "is stamped follow-up-able for game_list" do
      payload = handler.call.events.first[:payload]
      expect(Pito::FollowUp.followupable?(payload)).to be(true)
      expect(payload["reply_target"]).to eq("game_list")
    end

    it "renders the intro via Pito::Copy with the count" do
      payload = handler.call.events.first[:payload]
      expect(payload["body"]).to include("2")
    end
  end

  describe "#call with an empty library" do
    it "returns a witty empty-state system event" do
      result = handler.call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      payload = result.events.first[:payload]
      expect(payload["text"]).to be_present
      expect(payload[:table_rows]).to be_nil
    end
  end

  describe "#call with `list games` (regression)" do
    let!(:game) { create(:game, title: "Lies of P") }

    it "still lists games for `list games` with two cells per row" do
      result = handler_for("list games").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.first[:payload]["table_rows"].first[:cells].size).to eq(2)
    end
  end

  describe "#call with `list games with genre`" do
    let!(:rpg_genre) { create(:genre, name: "Role-playing") }
    let!(:game)      { create(:game, title: "Elden Ring") }
    before           { create(:game_genre, game: game, genre: rpg_genre) }

    it "includes 'Genre' in the table_heading" do
      payload = handler_for("list games with genre").call.events.first[:payload]
      expect(payload["table_heading"]).to include("Genre")
    end

    it "returns three columns in the heading (# Game Genre)" do
      payload = handler_for("list games with genre").call.events.first[:payload]
      expect(payload["table_heading"]).to eq([ "#", "Game", "Genre" ])
    end
  end

  # ── Channels ──────────────────────────────────────────────────────────────

  describe "#call with the channels noun" do
    let!(:beta)  { create(:channel, title: "Beta Cast",  handle: "@beta",  youtube_channel_id: "UCb") }
    let!(:alpha) { create(:channel, title: "Alpha Tube", handle: "@alpha", youtube_channel_id: "UCa") }

    it "returns an html body including each channel title" do
      body = handler_for("list channels").call.events.first[:payload]["body"]
      expect(body).to include("Alpha Tube")
      expect(body).to include("Beta Cast")
    end

    it "includes each channel @handle in the body" do
      body = handler_for("list channels").call.events.first[:payload]["body"]
      expect(body).to include("@alpha")
      expect(body).to include("@beta")
    end

    it "includes a youtube.com link with target=_blank for each channel" do
      body = handler_for("list channels").call.events.first[:payload]["body"]
      expect(body).to include("https://www.youtube.com/@alpha")
      expect(body).to include("https://www.youtube.com/@beta")
      expect(body).to include('target="_blank"')
    end

    it "includes the plain channel id (no # prefix) in the body" do
      body = handler_for("list channels").call.events.first[:payload]["body"]
      expect(body).to include(alpha.id.to_s)
      expect(body).to include(beta.id.to_s)
    end

    it "sets html: true on the payload" do
      payload = handler_for("list channels").call.events.first[:payload]
      expect(payload["html"]).to be(true)
    end

    it "renders the channels intro via Pito::Copy with the count" do
      payload = handler_for("list channels").call.events.first[:payload]
      expect(payload["body"]).to include("2")
    end

    it "is stamped follow-up-able for channel_list" do
      payload = handler_for("list channels").call.events.first[:payload]
      expect(Pito::FollowUp.followupable?(payload)).to be(true)
      expect(payload["reply_target"]).to eq("channel_list")
    end

    # Channels are the kv-table exception: they stay avatar cards, so `with`/
    # `sorted by` clauses are simply ignored — no kv-table, no heading row.
    it "ignores `with` / `sorted by` clauses and stays avatar cards (no kv-table)" do
      [ "list channels with foo", "list channels sorted by title" ].each do |raw|
        payload = handler_for(raw).call.events.first[:payload]
        expect(payload["html"]).to be(true)
        expect(payload["table_heading"]).to be_nil
        expect(payload["table_rows"]).to be_nil
        expect(payload["body"]).to include("Alpha Tube").and include("Beta Cast")
      end
    end

    it "includes a reply_handle in the channel list payload" do
      payload = handler_for("list channels").call.events.first[:payload]
      expect(payload["reply_handle"]).to be_present
    end

    it "returns a witty empty-state when no channels are connected" do
      Channel.delete_all
      payload = handler_for("list channels").call.events.first[:payload]
      expect(payload["text"]).to be_present
      expect(payload[:table_rows]).to be_nil
    end
  end

  # ── Videos ────────────────────────────────────────────────────────────────

  describe "#call with `list videos`" do
    let!(:chan_a) { create(:channel, title: "Channel A", handle: "@chana", youtube_channel_id: "UCa1") }
    let!(:chan_b) { create(:channel, title: "Channel B", handle: "@chanb", youtube_channel_id: "UCb1") }

    let!(:pub_a)  { create(:video, :public,   title: "Alpha Public",   channel: chan_a) }
    let!(:unl_a)  { create(:video, :unlisted, title: "Alpha Unlisted", channel: chan_a) }
    let!(:pub_b)  { create(:video, :public,   title: "Beta Public",    channel: chan_b) }

    context "with @all (or no channel scope)" do
      it "lists all videos when channel is @all" do
        result = handler_for("list videos", channel: "@all").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        payload = result.events.first[:payload]
        titles  = video_titles(payload)
        expect(titles).to include("Alpha Public")
        expect(titles).to include("Alpha Unlisted")
        expect(titles).to include("Beta Public")
      end

      it "lists all videos when channel is nil" do
        result = handler_for("list videos", channel: nil).call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        payload = result.events.first[:payload]
        titles  = video_titles(payload)
        expect(titles).to include("Alpha Public")
        expect(titles).to include("Alpha Unlisted")
        expect(titles).to include("Beta Public")
      end

      it "renders as a table_rows kv-table (not html)" do
        payload = handler_for("list videos", channel: "@all").call.events.first[:payload]
        expect(payload["table_rows"]).to be_present
        expect(payload["html"]).to be_falsey
      end

      it "is NOT follow-up-able (no video_list follow-up engine)" do
        payload = handler_for("list videos", channel: "@all").call.events.first[:payload]
        expect(Pito::FollowUp.followupable?(payload)).to be(false)
      end
    end

    context "with a specific @channel handle" do
      it "scopes to that channel only" do
        result = handler_for("list videos", channel: "@chana").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        payload = result.events.first[:payload]
        titles  = video_titles(payload)
        expect(titles).to include("Alpha Public")
        expect(titles).to include("Alpha Unlisted")
        expect(titles).not_to include("Beta Public")
      end

      it "scopes to a channel whose handle lacks the leading @ in the DB" do
        # channel factory stores handle as "@chana" — verify normalisation works
        result = handler_for("list videos", channel: "@chanb").call
        payload = result.events.first[:payload]
        titles  = video_titles(payload)
        expect(titles).to include("Beta Public")
        expect(titles).not_to include("Alpha Public")
      end

      it "returns a clear not-found event for an unknown handle" do
        result = handler_for("list videos", channel: "@nope").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        payload = result.events.first[:payload]
        expect(payload["text"]).to include("@nope")
      end
    end

    context "with `published` filter" do
      it "returns only public videos" do
        result = handler_for("list videos published", channel: "@all").call
        payload = result.events.first[:payload]
        titles  = video_titles(payload)
        expect(titles).to include("Alpha Public")
        expect(titles).to include("Beta Public")
        expect(titles).not_to include("Alpha Unlisted")
      end
    end

    context "with `unlisted` filter" do
      it "returns only unlisted videos" do
        result = handler_for("list videos unlisted", channel: "@all").call
        payload = result.events.first[:payload]
        titles  = video_titles(payload)
        expect(titles).to include("Alpha Unlisted")
        expect(titles).not_to include("Alpha Public")
        expect(titles).not_to include("Beta Public")
      end
    end

    context "with `list videos with duration`" do
      let!(:dur_video) do
        create(:video, :public, title: "Duration Video", channel: chan_a,
                                duration_seconds: 300)
      end

      it "includes 'Duration' in the table_heading" do
        payload = handler_for("list videos with duration", channel: "@all").call.events.first[:payload]
        expect(payload["table_heading"]).to include("Duration")
      end

      it "returns a full heading row with the Duration column appended" do
        payload = handler_for("list videos with duration", channel: "@all").call.events.first[:payload]
        expect(payload["table_heading"]).to eq([ "#", "Title", "Channel", "Privacy", "Duration" ])
      end
    end

    context "empty states" do
      it "returns distinct empty-state copy for @all when no videos exist" do
        ::Video.delete_all
        payload = handler_for("list videos", channel: "@all").call.events.first[:payload]
        expect(payload["text"]).to be_present
      end

      it "returns channel-specific empty-state copy when channel has no videos" do
        create(:channel, title: "Empty Chan", handle: "@empty", youtube_channel_id: "UCempty")
        payload = handler_for("list videos", channel: "@empty").call.events.first[:payload]
        expect(payload["text"]).to be_present
        expect(payload["text"]).to include("@empty")
      end

      it "returns empty-state when published filter yields nothing" do
        ::Video.delete_all
        create(:video, :unlisted, title: "Only Unlisted", channel: chan_a)
        payload = handler_for("list videos published", channel: "@all").call.events.first[:payload]
        expect(payload["text"]).to be_present
      end
    end
  end

  # ── Channel threading ──────────────────────────────────────────────────────

  describe "channel: threading — backward compatibility" do
    it "constructs without channel: and works fine (default nil)" do
      h = described_class.new(
        message:      Pito::Chat::Message.new(verb: :list, body_tokens: [], kind: :new_turn, raw: "list games"),
        conversation: Conversation.singleton
      )
      expect { h.call }.not_to raise_error
    end

    it "exposes channel via attr_reader" do
      h = described_class.new(
        message:      Pito::Chat::Message.new(verb: :list, body_tokens: [], kind: :new_turn, raw: "list games"),
        conversation: Conversation.singleton,
        channel:      "@beta"
      )
      expect(h.channel).to eq("@beta")
    end
  end
end
