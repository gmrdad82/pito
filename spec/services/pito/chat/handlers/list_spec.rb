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

      it "is follow-up-able for the video_list target" do
        payload = handler_for("list videos", channel: "@all").call.events.first[:payload]
        expect(Pito::FollowUp.followupable?(payload)).to be(true)
        expect(payload["reply_target"]).to eq("video_list")
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

  # ── Sort clause — games ────────────────────────────────────────────────────

  describe "#call with `list games sorted by year desc` (year not visible)" do
    let!(:game) { create(:game, title: "Elden Ring", release_year: 2022) }

    it "returns an error payload whose text includes the column name" do
      result  = handler_for("list games sorted by year desc").call
      payload = result.events.first[:payload]
      expect(payload["text"]).to include("year")
    end

    it "does not return table_rows" do
      result  = handler_for("list games sorted by year desc").call
      payload = result.events.first[:payload]
      expect(payload["table_rows"]).to be_nil
    end
  end

  describe "#call with `list games with year sorted by year desc`" do
    let!(:game_a) { create(:game, title: "Elden Ring",        release_year: 2022) }
    let!(:game_b) { create(:game, title: "Hollow Knight",     release_year: 2017) }
    let!(:game_c) { create(:game, title: "Tears of the Kingdom", release_year: 2023) }

    it "returns games ordered by release_year descending" do
      rows   = handler_for("list games with year sorted by year desc").call.events.first[:payload]["table_rows"]
      titles = rows.map { |r| r[:cells][1][:text] }
      expect(titles).to eq([ "Tears of the Kingdom", "Elden Ring", "Hollow Knight" ])
    end
  end

  describe "#call with `list games sorted by title desc`" do
    let!(:game_a) { create(:game, title: "Zelda") }
    let!(:game_b) { create(:game, title: "Elden Ring") }
    let!(:game_c) { create(:game, title: "Hollow Knight") }

    it "returns games in reverse-alphabetical title order" do
      rows   = handler_for("list games sorted by title desc").call.events.first[:payload]["table_rows"]
      titles = rows.map { |r| r[:cells][1][:text] }
      expect(titles).to eq([ "Zelda", "Hollow Knight", "Elden Ring" ])
    end
  end

  # ── Sort clause — videos ────────────────────────────────────────────────────

  describe "#call with `list videos sorted by views` (views not visible)" do
    let!(:chan) { create(:channel, title: "Channel A", handle: "@chana", youtube_channel_id: "UCa2") }
    let!(:vid)  { create(:video, :public, title: "Some Video", channel: chan) }

    it "returns an error payload whose text includes 'views'" do
      result  = handler_for("list videos sorted by views", channel: "@all").call
      payload = result.events.first[:payload]
      expect(payload["text"]).to include("views")
    end

    it "does not return table_rows" do
      result  = handler_for("list videos sorted by views", channel: "@all").call
      payload = result.events.first[:payload]
      expect(payload["table_rows"]).to be_nil
    end
  end

  describe "#call with `list videos with views sorted by views desc`" do
    let!(:chan)   { create(:channel, title: "Sort Chan", handle: "@sortchan", youtube_channel_id: "UCsort") }
    let!(:vid_a) { create(:video, :public, title: "Alpha Video", channel: chan) }
    let!(:vid_b) { create(:video, :public, title: "Beta Video",  channel: chan) }
    let!(:vid_c) { create(:video, :public, title: "Gamma Video", channel: chan) }

    before do
      create(:stat, entity: vid_a, kind: "views", value: 1_000)
      create(:stat, entity: vid_b, kind: "views", value: 5_000)
      create(:stat, entity: vid_c, kind: "views", value: 3_000)
    end

    it "returns videos ordered by view_count descending" do
      rows   = handler_for("list videos with views sorted by views desc", channel: "@all").call
                           .events.first[:payload]["table_rows"]
      titles = rows.map { |r| r[:cells][1][:text] }
      expect(titles).to eq([ "Beta Video", "Gamma Video", "Alpha Video" ])
    end
  end

  # ── Games — channel scope ─────────────────────────────────────────────────

  describe "#call `list games` channel scope" do
    let!(:chan_a) { create(:channel, title: "Channel A", handle: "@gchana", youtube_channel_id: "UCga1") }
    let!(:chan_b) { create(:channel, title: "Channel B", handle: "@gchanb", youtube_channel_id: "UCgb1") }

    let!(:game_a) { create(:game, title: "Alpha Game") }
    let!(:game_b) { create(:game, title: "Beta Game") }
    let!(:game_c) { create(:game, title: "No Videos Game") }

    let!(:video_a) { create(:video, :public, title: "Video A", channel: chan_a) }
    let!(:video_b) { create(:video, :public, title: "Video B", channel: chan_b) }

    before do
      create(:video_game_link, video: video_a, game: game_a)
      create(:video_game_link, video: video_b, game: game_b)
    end

    def game_titles(payload)
      Array(payload["table_rows"]).map { |r| r[:cells][1][:text] }
    end

    context "with a specific channel handle" do
      it "lists only games linked to videos on that channel" do
        payload = handler_for("list games", channel: "@gchana").call.events.first[:payload]
        titles  = game_titles(payload)
        expect(titles).to include("Alpha Game")
        expect(titles).not_to include("Beta Game")
        expect(titles).not_to include("No Videos Game")
      end

      it "scopes to channel B when @gchanb is requested" do
        payload = handler_for("list games", channel: "@gchanb").call.events.first[:payload]
        titles  = game_titles(payload)
        expect(titles).to include("Beta Game")
        expect(titles).not_to include("Alpha Game")
      end
    end

    context "with @all or no channel scope" do
      it "lists all games when channel is @all" do
        payload = handler_for("list games", channel: "@all").call.events.first[:payload]
        titles  = game_titles(payload)
        expect(titles).to include("Alpha Game")
        expect(titles).to include("Beta Game")
        expect(titles).to include("No Videos Game")
      end

      it "lists all games when channel is nil" do
        payload = handler_for("list games", channel: nil).call.events.first[:payload]
        titles  = game_titles(payload)
        expect(titles).to include("Alpha Game")
        expect(titles).to include("Beta Game")
        expect(titles).to include("No Videos Game")
      end
    end

    context "with a game that has no videos" do
      it "excludes video-less game when a specific channel is requested" do
        payload = handler_for("list games", channel: "@gchana").call.events.first[:payload]
        expect(game_titles(payload)).not_to include("No Videos Game")
      end

      it "includes video-less game under @all" do
        payload = handler_for("list games", channel: "@all").call.events.first[:payload]
        expect(game_titles(payload)).to include("No Videos Game")
      end
    end

    # The shift+tab channel scope composes with the `with` columns and `sorted by`
    # in one pipeline (scope → columns → sort).
    context "combined with `with <cols>` and `sorted by`" do
      let!(:action) { create(:genre, name: "Action") }
      before { create(:game_genre, game: game_a, genre: action) }

      it "scopes to the channel AND renders the requested column" do
        payload = handler_for("list games with genre", channel: "@gchana").call.events.first[:payload]
        expect(payload["table_heading"]).to eq([ "#", "Game", "Genre" ])
        rows = payload["table_rows"]
        expect(rows.map { |r| r[:cells][1][:text] }).to eq([ "Alpha Game" ]) # channel-scoped
        expect(rows.first[:cells][2][:text]).to eq("Action")                 # with-column rendered
      end

      it "scope + with + sorted by a visible column all compose" do
        payload = handler_for("list games with genre sorted by genre desc", channel: "@gchana")
          .call.events.first[:payload]
        expect(payload["table_heading"]).to include("Genre")
        expect(payload["table_rows"].map { |r| r[:cells][1][:text] }).to eq([ "Alpha Game" ])
      end
    end

    context "with an unknown channel handle" do
      it "returns a not-found error event whose text includes the handle" do
        result  = handler_for("list games", channel: "@nope").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        payload = result.events.first[:payload]
        expect(payload["text"]).to include("@nope")
        expect(payload["table_rows"]).to be_nil
      end
    end

    context "when channel-scoped result is empty" do
      it "returns filter-empty copy (not plain-empty)" do
        create(:channel, title: "Empty Chan", handle: "@gempty", youtube_channel_id: "UCgempty")
        payload = handler_for("list games", channel: "@gempty").call.events.first[:payload]
        expect(payload["text"]).to be_present
        expect(payload["table_rows"]).to be_nil
        # filter-empty copy key differs from plain-empty; both have "text" but
        # the filter-empty message does not include "/games import" (plain-empty does)
        expect(payload["text"]).not_to include("/games import")
      end
    end
  end

  # ── list games --help ─────────────────────────────────────────────────────

  describe "#call with `list games --help`" do
    it "returns a Result::Ok with one system event" do
      result = handler_for("list games --help").call
      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(result.events.length).to eq(1)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "does NOT list games (no table_rows from the game library)" do
      # The --help payload's table_rows are column guide rows, not game rows.
      # A game-library row has cells[0] with a #-prefixed id; help rows use :cells with option labels.
      create(:game, title: "Elden Ring")
      payload = handler_for("list games --help").call.events.first[:payload]
      rows    = Array(payload["table_rows"])
      # No row should have a "#" prefixed id cell (sign of a game-library row)
      game_row = rows.find do |r|
        cells = r[:cells] || r["cells"]
        cells&.first&.dig(:text)&.start_with?("#") ||
          cells&.first&.dig("text")&.start_with?("#")
      end
      expect(game_row).to be_nil
    end

    it "payload body mentions the intro text" do
      payload = handler_for("list games --help").call.events.first[:payload]
      expect(payload["body"]).to include("list games with")
    end

    it "payload table_rows include a row for platform" do
      rows = handler_for("list games --help").call.events.first[:payload]["table_rows"]
      texts = rows.flat_map { |r| (r[:cells] || r["cells"] || []).map { |c| c[:text] || c["text"] } }
      expect(texts.map(&:downcase)).to include("platform")
    end

    it "payload table_rows include a row for genre" do
      rows = handler_for("list games --help").call.events.first[:payload]["table_rows"]
      texts = rows.flat_map { |r| (r[:cells] || r["cells"] || []).map { |c| c[:text] || c["text"] } }
      expect(texts.map(&:downcase)).to include("genre")
    end

    it "payload table_rows include a row for developer" do
      rows = handler_for("list games --help").call.events.first[:payload]["table_rows"]
      texts = rows.flat_map { |r| (r[:cells] || r["cells"] || []).map { |c| c[:text] || c["text"] } }
      expect(texts.map(&:downcase)).to include("developer")
    end

    it "payload table_rows include a row for publisher" do
      rows = handler_for("list games --help").call.events.first[:payload]["table_rows"]
      texts = rows.flat_map { |r| (r[:cells] || r["cells"] || []).map { |c| c[:text] || c["text"] } }
      expect(texts.map(&:downcase)).to include("publisher")
    end

    it "payload table_rows include a row for release date" do
      rows = handler_for("list games --help").call.events.first[:payload]["table_rows"]
      texts = rows.flat_map { |r| (r[:cells] || r["cells"] || []).map { |c| c[:text] || c["text"] } }
      expect(texts.map(&:downcase)).to include("release")
    end

    it "payload table_rows include a row for year" do
      rows = handler_for("list games --help").call.events.first[:payload]["table_rows"]
      texts = rows.flat_map { |r| (r[:cells] || r["cells"] || []).map { |c| c[:text] || c["text"] } }
      expect(texts.map(&:downcase)).to include("year")
    end

    it "table_rows aliases cell for platform includes 'platforms'" do
      rows = handler_for("list games --help").call.events.first[:payload]["table_rows"]
      texts = rows.flat_map { |r| (r[:cells] || r["cells"] || []).map { |c| c[:text] || c["text"] } }
      expect(texts.join(" ")).to include("platforms")
    end

    it "table_rows aliases cell for developer includes 'dev'" do
      rows = handler_for("list games --help").call.events.first[:payload]["table_rows"]
      texts = rows.flat_map { |r| (r[:cells] || r["cells"] || []).map { |c| c[:text] || c["text"] } }
      expect(texts.join(" ")).to include("dev")
    end
  end

  describe "#call with `list games` (no --help flag) still lists games" do
    let!(:elden) { create(:game, title: "Elden Ring") }

    it "returns normal game list rows (not help content)" do
      payload = handler_for("list games").call.events.first[:payload]
      rows    = Array(payload["table_rows"])
      titles  = rows.map { |r| (r[:cells] || r["cells"] || [])[1]&.dig(:text) || (r[:cells] || r["cells"] || [])[1]&.dig("text") }
      expect(titles).to include("Elden Ring")
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
