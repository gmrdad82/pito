# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Chat::Handlers::List do
  subject(:handler) do
    described_class.new(
      message: Pito::Chat::Message.new(tool: :list, body_tokens: [], kind: :new_turn, raw: "list games"),
      conversation: Conversation.singleton
    )
  end

  def handler_for(raw, channel: nil, viewport_width: nil)
    described_class.new(
      message:        Pito::Chat::Message.new(tool: :list, body_tokens: [], kind: :new_turn, raw:),
      conversation:   Conversation.singleton,
      channel:        channel,
      viewport_width: viewport_width
    )
  end

  def video_titles(payload)
    Array(payload["table_rows"]).map { |row| row[:cells][1][:text] }
  end

  # ── Explicit ids: `list videos 2, #4, 7` → exactly those, typed order ────────

  describe "list <noun> <ids>" do
    let!(:ch) { create(:channel) }
    let!(:v1) { create(:video, channel: ch, title: "One") }
    let!(:v2) { create(:video, channel: ch, title: "Two") }
    let!(:v3) { create(:video, channel: ch, title: "Three") }

    it "lists exactly the named vids in the typed order" do
      payload = handler_for("list videos #{v3.id}, ##{v1.id}").call.events.first[:payload]
      expect(video_titles(payload)).to eq(%w[Three One])
    end

    it "still works for a single id" do
      payload = handler_for("list videos #{v2.id}").call.events.first[:payload]
      expect(video_titles(payload)).to eq(%w[Two])
    end

    it "bypasses the channel scope (you named the rows)" do
      other = create(:channel, handle: "@other")
      payload = handler_for("list videos #{v1.id}", channel: other.at_handle).call.events.first[:payload]
      expect(video_titles(payload)).to eq(%w[One])
    end

    it "lists games by id too" do
      g1 = create(:game, title: "Alpha")
      g2 = create(:game, title: "Beta")
      payload = handler_for("list games #{g2.id}, #{g1.id}").call.events.first[:payload]
      titles  = Array(payload["table_rows"]).map { |r| r[:cells][1][:text] }
      expect(titles).to eq(%w[Beta Alpha])
    end
  end

  # ── Width-aware default columns ─────────────────────────────────────────────

  describe "width-aware default columns" do
    let!(:wgame) { create(:game, title: "Width Game") }

    it "auto-adds columns on a wide viewport when no `with` is given" do
      payload = handler_for("list games", viewport_width: 1300).call.events.first[:payload]
      expect(payload["list_columns"].size).to be > 2
    end

    it "keeps the lean id+title default when the width is absent" do
      payload = handler_for("list games", viewport_width: nil).call.events.first[:payload]
      expect(payload["list_columns"]).to eq([])
    end

    it "keeps the lean default on a too-narrow viewport" do
      payload = handler_for("list games", viewport_width: 300).call.events.first[:payload]
      expect(payload["list_columns"]).to eq([])
    end

    it "lets an explicit `with` clause override the auto-fill" do
      payload = handler_for("list games with genre", viewport_width: 1300).call.events.first[:payload]
      expect(payload["list_columns"]).to eq([ "genre" ])
    end

    it "caps the auto-fill at the data-grid's max (6 added) even on a huge viewport" do
      payload = handler_for("list games", viewport_width: 5000).call.events.first[:payload]
      all = Pito::MessageBuilder::Game::ListColumns::COLUMNS.keys.map(&:to_s)
      expect(payload["list_columns"]).to eq(all.first(6))
      # id + title + added must stay within the grid's data-cols="8" templates.
      expect(payload["list_columns"].size + 2).to be <= 8
    end
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

  # ── Upcoming bypasses the channel scope ─────────────────────────────────────

  describe "#call list games upcoming bypasses the channel scope" do
    let!(:solo)          { create(:channel, handle: "@solo", youtube_channel_id: "UCsolo") }
    let!(:solo_vid)      { create(:video, :public, channel: solo) }
    let!(:linked_game)   { create(:game, title: "Linked Released", release_year: 2020) }
    # An upcoming (TBA) game with NO game↔vid links — a channel scope would
    # exclude it because it can't be linked to any video.
    let!(:upcoming_game) { create(:game, title: "Upcoming Quest", release_year: nil, release_date: nil) }

    before { VideoGameLink.create!(video: solo_vid, game: linked_game) }

    def titles(raw, channel:)
      handler_for(raw, channel: channel).call.events
        .flat_map { |e| Array(e[:payload]["table_rows"]) }
        .map { |r| r[:cells][1][:text] }
    end

    it "shows upcoming games under a specific shift+tab channel (no link required)" do
      expect(titles("list games upcoming", channel: "@solo")).to include("Upcoming Quest")
    end

    it "still channel-scopes a NON-upcoming list (only games linked to that channel's vids)" do
      result = titles("list games", channel: "@solo")
      expect(result).to include("Linked Released")
      expect(result).not_to include("Upcoming Quest")
    end
  end

  describe "#call list games upcoming → horizon-split PAIR (:system soon / :enhanced later)" do
    def dated_game(title, on)
      create(:game, title:, release_year: on.year, release_month: on.month, release_day: on.day)
    end

    def row_titles(payload)
      payload["table_rows"].to_a.map { |r| r[:cells][1][:text] }
    end

    let!(:soon)  { dated_game("Soon Quest",  Date.current + 10) }   # within 30d
    let!(:later) { dated_game("Later Saga",  Date.current + 200) }  # beyond 30d
    let!(:tba)   { create(:game, :tba, title: "Maybe Never") }      # undated → later

    let(:events) { handler_for("list games upcoming").call.events }

    it "emits TWO messages: a :system soon card and an :enhanced later card" do
      expect(events.map { |e| e[:kind] }).to eq([ :system, :enhanced ])
    end

    it "puts only games releasing within 30 days in the :system card" do
      expect(row_titles(events[0][:payload])).to eq([ "Soon Quest" ])
    end

    it "puts later-dated AND undated/TBA games in the :enhanced card" do
      expect(row_titles(events[1][:payload])).to contain_exactly("Later Saga", "Maybe Never")
    end

    it "places a game on the 30-day boundary in soon, the day after in later" do
      on_boundary = dated_game("Edge In",  Date.current + 30)
      day_after   = dated_game("Edge Out", Date.current + 31)
      ev = handler_for("list games upcoming").call.events
      expect(row_titles(ev[0][:payload])).to include("Edge In").and(include("Soon Quest"))
      expect(row_titles(ev[0][:payload])).not_to include("Edge Out")
      expect(row_titles(ev[1][:payload])).to include("Edge Out")
    end

    it "renders each intro with the horizon as a subject-shimmer token" do
      expect(events[0][:payload]["body"]).to include("pito-subject-shimmer")
      expect(events[1][:payload]["body"]).to include("pito-subject-shimmer")
    end

    it "ALWAYS emits the pair: empty :system gets an ironic empty-state message (no table)" do
      soon.destroy
      ev = handler_for("list games upcoming").call.events
      expect(ev.map { |e| e[:kind] }).to eq([ :system, :enhanced ])    # still the pair
      expect(ev[0][:payload]["table_rows"]).to be_nil                  # empty soon → no table
      expect(ev[0][:payload]["body"]).to include("pito-subject-shimmer")
      expect(row_titles(ev[1][:payload])).to contain_exactly("Later Saga", "Maybe Never")
    end

    it "ALWAYS emits the pair: empty :enhanced gets an ironic empty-state message (no table)" do
      later.destroy
      tba.destroy
      ev = handler_for("list games upcoming").call.events
      expect(ev.map { |e| e[:kind] }).to eq([ :system, :enhanced ])    # still the pair
      expect(row_titles(ev[0][:payload])).to eq([ "Soon Quest" ])
      expect(ev[1][:payload]["table_rows"]).to be_nil                  # empty later → no table
      expect(ev[1][:payload]["body"]).to include("pito-subject-shimmer")
    end
  end

  describe "upcoming copy dictionaries" do
    it "expose 50 variants each (intro + empty, soon + later), all carrying %{horizon}" do
      %w[
        pito.copy.games.upcoming.soon.intro pito.copy.games.upcoming.soon.empty
        pito.copy.games.upcoming.later.intro pito.copy.games.upcoming.later.empty
      ].each do |key|
        variants = I18n.t(key)
        expect(variants.size).to eq(50)
        expect(variants).to all(include("%{horizon}"))
      end
    end
  end

  # ── Unknown list target → no-guess (huh) ─────────────────────────────────────
  #
  # Owner 2026-06-29: a genuinely unknown word (neither an entity noun nor a
  # recognised game filter, and not a near-miss typo) no longer silently lists ALL
  # games — it returns the generic `pito.copy.huh` error. Bare `list`, entity nouns,
  # and valid filters (`list rpg`) are unaffected (covered below).

  describe "#call with a genuinely unknown word → unknown_entity (huh), no guess" do
    let!(:game) { create(:game, title: "Tears of the Kingdom") }

    it "a truly-unknown token (`list asd`) → huh error, not a silent list-all" do
      result = handler_for("list asd").call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(I18n.t("pito.copy.huh")).to include(result.message_key)
    end

    it "conversational filler (`list games please yo`) → huh error" do
      result = handler_for("list games please yo").call
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(I18n.t("pito.copy.huh")).to include(result.message_key)
    end

    # ── NL soft-fail marker (3.0.1 P7) ─────────────────────────────────────────
    # In free chat this branch flags its huh error as an nl_fallback marker so
    # Pito::Dispatch::Router gives the original utterance one shot at the NL
    # gate before the huh copy renders. Follow-up replies stay a plain error.

    it "flags the free-chat huh error as an nl_fallback marker" do
      result = handler_for("list asd").call
      expect(result.nl_fallback).to be(true)
    end

    it "keeps a follow-up reply's huh error un-flagged (machine-reconstructed input, never free text)" do
      source = Struct.new(:payload).new({ "reply_target" => "game_list" })
      fu     = Pito::Chat::FollowUpContext.new(source_event: source, rest: "asd")
      follow_up_handler = described_class.new(
        message:      Pito::Chat::Message.new(tool: :list, body_tokens: [], kind: :new_turn, raw: "list asd"),
        conversation: Conversation.singleton,
        follow_up:    fu
      )

      result = follow_up_handler.send(:unknown_entity)
      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.nl_fallback).to be(false)
    end

    it "still lists games for a bare `list`" do
      expect(handler_for("list").call.events.first[:payload]["table_rows"]).to be_present
    end

    it "still lists games for `list games`" do
      expect(handler_for("list games").call.events.first[:payload]["table_rows"]).to be_present
    end

    it "accepts `gamez` as a synonym for `games` and lists games" do
      expect(handler_for("list gamez").call.events.first[:payload]["table_rows"]).to be_present
    end

    it "does not correct a valid filter token like `upcoming`" do
      payload  = handler_for("list upcoming").call.events.first[:payload]
      combined = "#{payload['text']}#{payload['body']}"
      expect(combined).not_to include("Did you mean")
    end
  end

  # ── Did-you-mean (fuzzy correction of near-miss vocabulary) ──────────────────

  describe "#call with a near-miss token (did-you-mean)" do
    let!(:game) { create(:game, title: "Tears of the Kingdom") }

    it "offers `rpg` for the genre typo `list rpgg` instead of listing" do
      payload = handler_for("list rpgg").call.events.first[:payload]
      expect(payload["text"]).to include("Did you mean")
      expect(payload["text"]).to include("rpg")
      expect(payload["table_rows"]).to be_blank
    end

    it "offers `playstation` for the platform typo `list playstaton`" do
      payload = handler_for("list playstaton").call.events.first[:payload]
      expect(payload["text"]).to include("playstation")
      expect(payload["table_rows"]).to be_blank
    end

    it "offers `switch` for the platform typo `list swith`" do
      payload = handler_for("list swith").call.events.first[:payload]
      expect(payload["text"]).to include("switch")
      expect(payload["table_rows"]).to be_blank
    end

    it "fuzzy-corrects the noun typo `list vidoes` and routes to the vids path" do
      # "vidoes" (6 chars, threshold 2) is dist-2 from "vids" — fuzzy correction
      # routes directly to list_videos with a correction note rather than
      # offering a GameListFilter "did you mean" suggestion.
      result = handler_for("list vidoes").call
      note = result.events.first
      expect(note[:kind]).to eq(:system)
      expect(note[:payload]["text"].to_s).to include("vidoes")
    end
  end

  # ── Singular noun aliases route via the shared registry ─────────────────────

  describe "#call with singular noun aliases" do
    let!(:chan)  { create(:channel, title: "Solo Chan", handle: "@solo", youtube_channel_id: "UCsolo") }
    let!(:video) { create(:video, :public, title: "Solo Video", channel: chan) }

    it "routes `list video` to the video list (not a games table)" do
      payload = handler_for("list video", channel: "@all").call.events.first[:payload]
      expect(payload["reply_target"]).to eq("video_list")
      expect(video_titles(payload)).to include("Solo Video")
    end

    it "routes `list vid` to the video list" do
      payload = handler_for("list vid", channel: "@all").call.events.first[:payload]
      expect(payload["reply_target"]).to eq("video_list")
    end

    it "routes `list channel` to the channel list" do
      payload = handler_for("list channel").call.events.first[:payload]
      expect(payload["reply_target"]).to eq("channel_list")
    end
  end

  # ── Filler tolerance across nouns (e) ───────────────────────────────────────

  describe "#call tolerates filler on every noun" do
    let!(:chan)  { create(:channel, title: "Filler Chan", handle: "@filler", youtube_channel_id: "UCfiller") }
    let!(:video) { create(:video, :public, title: "Filler Video", channel: chan) }

    it "ignores filler on `list videos please` and still lists videos" do
      payload = handler_for("list videos please", channel: "@all").call.events.first[:payload]
      expect(video_titles(payload)).to include("Filler Video")
    end

    it "ignores filler on `list channels please` and still lists channels" do
      payload = handler_for("list channels please").call.events.first[:payload]
      titles  = payload["table_rows"].map { |r| r[:cells][2][:text] }
      expect(titles).to include("Filler Chan")
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
      heading_texts = payload["table_heading"].map { |h| h.is_a?(Hash) ? h["text"] : h }
      expect(heading_texts).to include("Genre")
    end

    it "returns three columns in the heading (# Game Genre)" do
      payload = handler_for("list games with genre").call.events.first[:payload]
      expect(payload["table_heading"]).to eq([
        { "text" => "#", "class" => "text-right" },
        "Game",
        { "text" => "Genre", "class" => "pito-table-heading--added" }
      ])
    end
  end

  # ── Channels ──────────────────────────────────────────────────────────────

  describe "#call with the channels noun" do
    let!(:beta)  { create(:channel, title: "Beta Cast",  handle: "@beta",  youtube_channel_id: "UCb") }
    let!(:alpha) { create(:channel, title: "Alpha Tube", handle: "@alpha", youtube_channel_id: "UCa") }

    # The kv-table (Phase LS): rows carry Avatar/Handle/Title/Subs/Views/Vids
    # cells; the body is the intro line only.
    def channel_rows(raw = "list channels")
      handler_for(raw).call.events.first[:payload]["table_rows"]
    end

    it "lists each channel title as a Title cell" do
      titles = channel_rows.map { |r| r[:cells][2][:text] }
      expect(titles).to contain_exactly("Alpha Tube", "Beta Cast")
    end

    it "lists each channel @handle as a Handle cell" do
      handles = channel_rows.map { |r| r[:cells][1][:text] }
      expect(handles).to contain_exactly("@alpha", "@beta")
    end

    it "makes each Handle cell run `show channel @handle` (prefill, not a YouTube link)" do
      cells = channel_rows.map { |r| r[:cells][1] }
      prefills = cells.map { |c| c[:data].to_h.values.join(" ") }
      expect(prefills.join(" ")).to include("show channel @alpha", "show channel @beta")
      expect(prefills.join(" ")).not_to include("https://www.youtube.com")
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

    # Channels have NO with/without (all columns always shown) — a `with`
    # clause is ignored and the table renders anyway.
    it "ignores a `with` clause and renders the table" do
      payload = handler_for("list channels with foo").call.events.first[:payload]
      expect(payload["table_rows"].size).to eq(2)
    end

    # ── sort (every column except Avatar) ────────────────────────────────────
    it "sorts by title ascending with `sorted by title`" do
      titles = channel_rows("list channels sorted by title").map { |r| r[:cells][2][:text] }
      expect(titles).to eq([ "Alpha Tube", "Beta Cast" ])
    end

    it "sorts by handle descending with `list channels sort handle desc`" do
      handles = channel_rows("list channels sort handle desc").map { |r| r[:cells][1][:text] }
      expect(handles).to eq([ "@beta", "@alpha" ])
    end

    it "accepts the canonical-noun aliases (subscribers → subs)" do
      payload = handler_for("list channels sort subscribers").call.events.first[:payload]
      expect(payload["table_rows"].size).to eq(2)
    end

    it "returns the channels-specific error (never suggesting `with`) for an unknown sort column" do
      payload = handler_for("list channels sort price").call.events.first[:payload]
      expect(payload["text"]).to include("price")
      expect(payload["text"]).not_to include("with")
      expect(payload["table_rows"]).to be_nil
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

  # ── Channels ordering by latest video published_at ───────────────────────────

  describe "#call `list channels` ordering by latest video published_at" do
    let!(:ch_newest) { create(:channel, title: "Newest Vid Chan", handle: "@newest") }
    let!(:ch_older)  { create(:channel, title: "Older Vid Chan",  handle: "@older") }
    let!(:ch_novid)  { create(:channel, title: "No Vid Chan",     handle: "@novid") }

    before do
      create(:video, channel: ch_newest, published_at: 3.days.ago)
      create(:video, channel: ch_older,  published_at: 10.days.ago)
      # ch_novid intentionally has no videos
    end

    it "orders channels newest-latest-vid first, no-vid channel last" do
      payload = handler_for("list channels").call.events.first[:payload]
      handles = payload["table_rows"].map { |r| r[:cells][1][:text] }
      expect(handles).to eq([ "@newest", "@older", "@novid" ])
    end
  end

  # ── Channels reauth hint ──────────────────────────────────────────────────────

  describe "#call `list channels` with reauth-needed connections" do
    let!(:ok_conn)     { create(:youtube_connection) }
    let!(:ok_ch)       { create(:channel, title: "Healthy Chan", handle: "@healthy", youtube_connection: ok_conn) }
    let!(:reauth_conn) { create(:youtube_connection, :needs_reauth) }
    let!(:reauth_ch)   { create(:channel, title: "Broken Chan", handle: "@broken", youtube_connection: reauth_conn) }

    it "emits two events when at least one channel needs reauth" do
      result = handler_for("list channels").call
      expect(result.events.length).to eq(2)
    end

    it "first event is :system (normal channel list)" do
      expect(handler_for("list channels").call.events.first[:kind]).to eq(:system)
    end

    it "second event is :enhanced" do
      expect(handler_for("list channels").call.events.second[:kind]).to eq(:enhanced)
    end

    it "enhanced payload body names the reauth channel handle" do
      body = handler_for("list channels").call.events.second[:payload]["body"]
      expect(body).to include("@broken")
    end

    it "enhanced payload body does NOT name the healthy channel" do
      body = handler_for("list channels").call.events.second[:payload]["body"]
      expect(body).not_to include("@healthy")
    end

    it "enhanced payload is html" do
      payload = handler_for("list channels").call.events.second[:payload]
      expect(payload["html"]).to be(true)
    end
  end

  describe "#call `list channels` with all connections healthy" do
    let!(:ok_conn) { create(:youtube_connection) }
    let!(:ok_ch)   { create(:channel, title: "Fine Chan", handle: "@fine", youtube_connection: ok_conn) }

    it "emits exactly one event (no enhanced reauth message)" do
      result = handler_for("list channels").call
      expect(result.events.length).to eq(1)
      expect(result.events.first[:kind]).to eq(:system)
    end
  end

  # ── `list games with channels` (column, NOT the channels noun) ──────────────
  describe "#call with `list games with channels` (regression: noun vs with-column)" do
    let(:connection) { create(:youtube_connection) }
    let!(:channel)   { create(:channel, handle: "@manfy", youtube_connection: connection) }
    let!(:game)      { create(:game, title: "Pragmata") }
    let!(:video)     { create(:video, channel: channel, title: "Pragmata gameplay") }
    before           { create(:video_game_link, game: game, video: video) }

    %w[channels channel].each do |word|
      it "routes `list games with #{word}` to the games list with a Channels column, not `list channels`" do
        payload  = handler_for("list games with #{word}").call.events.first[:payload]
        headings = Array(payload["table_heading"]).map { |c| c.is_a?(Hash) ? c["text"] : c }

        expect(headings.first).to eq("#")          # games kv-table, not channel avatar cards
        expect(headings).to include("Channels")
        expect(payload["table_rows"].first[:cells].last[:text]).to include("@manfy")
      end
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

      it "lists all videos for the canonical short noun `list vids`" do
        result  = handler_for("list vids", channel: "@all").call
        payload = result.events.first[:payload]
        expect(video_titles(payload)).to include("Alpha Public", "Beta Public")
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

      it "renders as a table_rows kv-table with an html shimmer intro" do
        payload = handler_for("list videos", channel: "@all").call.events.first[:payload]
        expect(payload["table_rows"]).to be_present
        expect(payload["html"]).to be true
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

    context "with `scheduled` filter" do
      let!(:future_vid) { create(:video, :scheduled, title: "Scheduled Future", channel: chan_a) }

      it "returns only scheduled videos (publish_at in the future)" do
        result  = handler_for("list videos scheduled", channel: "@all").call
        payload = result.events.first[:payload]
        titles  = video_titles(payload)
        expect(titles).to include("Scheduled Future")
        expect(titles).not_to include("Alpha Public")
        expect(titles).not_to include("Alpha Unlisted")
        expect(titles).not_to include("Beta Public")
      end

      it "composes with `with channel, visibility` — scheduled video listed; heading has Channel + Visibility" do
        result  = handler_for("list videos scheduled with channel, visibility", channel: "@all").call
        payload = result.events.first[:payload]
        titles  = video_titles(payload)
        expect(titles).to include("Scheduled Future")
        heading_texts = payload["table_heading"].map { |h| h.is_a?(Hash) ? h["text"] : h }
        expect(heading_texts).to include("Channel")
        expect(heading_texts).to include("Visibility")
      end

      it "composes with `with channel, status` — status alias still resolves to visibility heading" do
        result  = handler_for("list videos scheduled with channel, status", channel: "@all").call
        payload = result.events.first[:payload]
        heading_texts = payload["table_heading"].map { |h| h.is_a?(Hash) ? h["text"] : h }
        expect(heading_texts).to include("Channel")
        expect(heading_texts).to include("Visibility")
      end
    end

    # D2 rule: private = privacy_status private AND NOT scheduled. A scheduled
    # vid is privacy-private on YouTube too, but it must surface only under
    # `scheduled`, never under `private`.
    context "with `private` filter" do
      let!(:scheduled_vid) { create(:video, :scheduled, title: "Scheduled Not Private", channel: chan_a) }
      let!(:private_nil)   { create(:video, :private, title: "Private Nil Publish", channel: chan_a) }
      let!(:private_past)  { create(:video, :private, title: "Private Past Publish", publish_at: 1.hour.ago, channel: chan_a) }

      it "returns only privacy-private, non-scheduled videos (NULL or past publish_at)" do
        result  = handler_for("list vids private", channel: "@all").call
        payload = result.events.first[:payload]
        titles  = video_titles(payload)
        expect(titles).to include("Private Nil Publish", "Private Past Publish")
        expect(titles).not_to include("Scheduled Not Private")
        expect(titles).not_to include("Alpha Public")
        expect(titles).not_to include("Alpha Unlisted")
        expect(titles).not_to include("Beta Public")
      end

      it "also parses filter-before-noun phrasing (`ls private vids`)" do
        result  = handler_for("ls private vids", channel: "@all").call
        titles  = video_titles(result.events.first[:payload])
        expect(titles).to include("Private Nil Publish", "Private Past Publish")
        expect(titles).not_to include("Scheduled Not Private")
      end

      # 3.0.1 P11: `draft` is a token alias for the same private_unscheduled
      # scope — "ls draft vids" must filter EXACTLY like "ls private vids".
      it "'ls draft vids' filters identically to 'ls private vids' (draft alias — 3.0.1 P11)" do
        result  = handler_for("ls draft vids", channel: "@all").call
        titles  = video_titles(result.events.first[:payload])
        expect(titles).to include("Private Nil Publish", "Private Past Publish")
        expect(titles).not_to include("Scheduled Not Private")
      end
    end

    context "with `list videos with duration`" do
      let!(:dur_video) do
        create(:video, :public, title: "Duration Video", channel: chan_a,
                                duration_seconds: 300)
      end

      # G26.3 — the heading is "Duration" now (was "Length").
      it "includes a right-aligned 'Duration' in the table_heading" do
        payload = handler_for("list videos with duration", channel: "@all").call.events.first[:payload]
        expect(payload["table_heading"]).to include({ "text" => "Duration", "class" => "pito-table-heading--added text-right" })
      end

      it "returns a full heading row with the right-aligned Duration column appended" do
        payload = handler_for("list videos with duration", channel: "@all").call.events.first[:payload]
        expect(payload["table_heading"]).to eq([ { "text" => "#", "class" => "text-right" }, "Title", { "text" => "Duration", "class" => "pito-table-heading--added text-right" } ])
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

  describe "#call with `list games with footage sorted by footage desc`" do
    let!(:game_a) { create(:game, title: "Elden Ring",           footage_hours: 20) }
    let!(:game_b) { create(:game, title: "Hollow Knight",        footage_hours: 5) }
    let!(:game_c) { create(:game, title: "Tears of the Kingdom", footage_hours: 40) }

    it "returns games ordered by footage descending" do
      rows   = handler_for("list games with footage sorted by footage desc").call.events.first[:payload]["table_rows"]
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

  # ── `sort by` alias + `game` column regression ───────────────────────────
  #
  # Proves that `sort by` (uninflected) parses identically to `sorted by`,
  # and that the `game` column is NOT silently dropped from list_columns when
  # it appears alongside a sort clause.  The video_ids assertion enforces the
  # actual sort order so neither form can "pass" by returning an unsorted list.

  describe "#call `ls vids with views,likes,game sort by views desc` (sort-alias + game-column regression)" do
    let!(:chan)    { create(:channel, title: "Sort Alias Chan", handle: "@sortalias", youtube_channel_id: "UCsortalias") }
    let!(:low_vid) { create(:video, :public, title: "Low Views Vid",  channel: chan) }
    let!(:mid_vid) { create(:video, :public, title: "Mid Views Vid",  channel: chan) }
    let!(:hi_vid)  { create(:video, :public, title: "High Views Vid", channel: chan) }

    before do
      create(:stat, entity: low_vid, kind: "views", value:    500)
      create(:stat, entity: mid_vid, kind: "views", value:  3_000)
      create(:stat, entity: hi_vid,  kind: "views", value:  8_000)
    end

    context "with `sort by` (uninflected)" do
      subject(:payload) do
        handler_for("ls vids with views,likes,game sort by views desc", channel: "@all")
          .call.events.first[:payload]
      end

      it "includes views, likes, and game in list_columns (game not dropped)" do
        expect(payload["list_columns"]).to include("views", "likes", "game")
      end

      it "orders video_ids by view_count descending" do
        expect(payload["video_ids"]).to eq([ hi_vid.id, mid_vid.id, low_vid.id ])
      end
    end

    context "with `sorted by` (inflected — parity)" do
      subject(:payload) do
        handler_for("ls vids with views,likes,game sorted by views desc", channel: "@all")
          .call.events.first[:payload]
      end

      it "includes views, likes, and game in list_columns (parity with sort by)" do
        expect(payload["list_columns"]).to include("views", "likes", "game")
      end

      it "orders video_ids by view_count descending (parity with sort by)" do
        expect(payload["video_ids"]).to eq([ hi_vid.id, mid_vid.id, low_vid.id ])
      end
    end

    context "with `sort by views` (no direction — ascending)" do
      it "orders video_ids by view_count ascending" do
        payload = handler_for("ls vids with views,likes,game sort by views", channel: "@all")
                    .call.events.first[:payload]
        expect(payload["video_ids"]).to eq([ low_vid.id, mid_vid.id, hi_vid.id ])
      end
    end

    # G26.1 — the removed comments column is silently dropped from a with clause;
    # the surviving columns still land in list_columns.
    context "with the removed `comments` token in the with clause" do
      it "drops comments but keeps the valid columns" do
        payload = handler_for("ls vids with views,comments,game sort by views desc", channel: "@all")
                    .call.events.first[:payload]
        expect(payload["list_columns"]).to include("views", "game")
        expect(payload["list_columns"]).not_to include("comments")
      end
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
        expect(payload["table_heading"]).to eq([
          { "text" => "#", "class" => "text-right" },
          "Game",
          { "text" => "Genre", "class" => "pito-table-heading--added" }
        ])
        rows = payload["table_rows"]
        expect(rows.map { |r| r[:cells][1][:text] }).to eq([ "Alpha Game" ]) # channel-scoped
        expect(rows.first[:cells][2][:text]).to eq("Action")                 # with-column rendered
      end

      it "scope + with + sorted by a visible column all compose" do
        payload = handler_for("list games with genre sorted by genre desc", channel: "@gchana")
          .call.events.first[:payload]
        heading_texts = payload["table_heading"].map { |h| h.is_a?(Hash) ? h["text"] : h }
        expect(heading_texts).to include("Genre")
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

    it "is an html payload (nvim-style man page), not a game table" do
      create(:game, title: "Elden Ring")
      payload = handler_for("list games --help").call.events.first[:payload]
      expect(payload["html"]).to be(true)
      expect(payload["table_rows"]).to be_nil
      expect(payload["body"]).not_to include("Elden Ring")
    end

    it "renders Usage / Options / Columns sections" do
      body = handler_for("list games --help").call.events.first[:payload]["body"]
      expect(body).to include("Usage:")
      expect(body).to include("Options:")
      expect(body).to include("Columns:")
    end

    it "documents the with / sorted by / --help options" do
      body = handler_for("list games --help").call.events.first[:payload]["body"]
      expect(body).to include("sorted by")
      expect(body).to include("--help")
      # `with <columns>` is html-escaped in the body
      expect(body).to include("with &lt;columns&gt;")
    end

    it "lists every optional column with its aliases (release/year removed — item 24)" do
      body = handler_for("list games --help").call.events.first[:payload]["body"]
      %w[platform genre developer publisher footage price].each { |col| expect(body).to include(col) }
      expect(body).not_to include("release date")
      # aliases are present too
      expect(body).to include("platforms")
      expect(body).to include("dev")
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

  # ── Default id-DESC sort order ────────────────────────────────────────────
  #
  # The default sort for all three list nouns is id DESC (biggest/newest first).
  # Tests below verify this by creating records where title-ASC would produce the
  # opposite order — proving id-DESC (not title-ASC) is the active default.
  # A second group asserts that an explicit `sorted by` clause overrides it.

  describe "default id-DESC sort order — games" do
    # alpha_game is created first (lower id); zebra_game second (higher id).
    # id-DESC puts zebra_game first; title-ASC would put alpha_game first.
    let!(:alpha_game) { create(:game, title: "Alpha Default Game") }
    let!(:zebra_game) { create(:game, title: "Zebra Default Game") }

    it "returns games in id-DESC order (highest id first) by default" do
      rows   = handler_for("list games").call.events.first[:payload]["table_rows"]
      titles = rows.map { |r| r[:cells][1][:text] }
      expect(titles).to eq([ "Zebra Default Game", "Alpha Default Game" ])
    end
  end

  describe "default id-DESC sort order — videos" do
    let!(:sort_chan) { create(:channel, title: "Sort Default Chan", handle: "@sort_default", youtube_channel_id: "UCsortdef1") }
    # alpha_vid is created first (lower id); zebra_vid second (higher id).
    # id-DESC puts zebra_vid first; title-ASC would put alpha_vid first.
    let!(:alpha_vid) { create(:video, :public, title: "Alpha Default Video", channel: sort_chan) }
    let!(:zebra_vid) { create(:video, :public, title: "Zebra Default Video", channel: sort_chan) }

    it "returns videos in id-DESC order (highest id first) by default" do
      payload = handler_for("list videos", channel: "@all").call.events.first[:payload]
      titles  = video_titles(payload)
      expect(titles).to eq([ "Zebra Default Video", "Alpha Default Video" ])
    end
  end

  describe "default id-DESC sort order — channels" do
    # alpha_ch is created first (lower id); zebra_ch second (higher id).
    # id-DESC must render @zebra_def before @alpha_def in the HTML body.
    let!(:alpha_ch) { create(:channel, title: "Alpha Default Chan", handle: "@alpha_def", youtube_channel_id: "UCadef1") }
    let!(:zebra_ch) { create(:channel, title: "Zebra Default Chan", handle: "@zebra_def", youtube_channel_id: "UCzdef1") }

    it "returns channels in id-DESC order (highest id first) by default" do
      rows    = handler_for("list channels").call.events.first[:payload]["table_rows"]
      handles = rows.map { |r| r[:cells][1][:text] }
      expect(handles.index("@zebra_def")).to be < handles.index("@alpha_def")
    end
  end

  describe "`list games sorted by title` overrides id-DESC default" do
    # alpha_game has lower id; zebra_game has higher id.
    # id-DESC default: Zebra first. sorted by title ASC: Alpha first.
    let!(:alpha_game) { create(:game, title: "Alpha Sort Override Game") }
    let!(:zebra_game) { create(:game, title: "Zebra Sort Override Game") }

    it "returns games in title-ASC order, not id-DESC" do
      rows   = handler_for("list games sorted by title").call.events.first[:payload]["table_rows"]
      titles = rows.map { |r| r[:cells][1][:text] }
      expect(titles).to eq([ "Alpha Sort Override Game", "Zebra Sort Override Game" ])
    end
  end

  describe "`list videos sorted by title` overrides id-DESC default" do
    let!(:sort_chan) { create(:channel, title: "Sort Override Chan", handle: "@sort_override", youtube_channel_id: "UCsortov1") }
    # alpha_vid has lower id; zebra_vid has higher id.
    # id-DESC default: Zebra first. sorted by title ASC: Alpha first.
    let!(:alpha_vid) { create(:video, :public, title: "Alpha Sort Override Video", channel: sort_chan) }
    let!(:zebra_vid) { create(:video, :public, title: "Zebra Sort Override Video", channel: sort_chan) }

    it "returns videos in title-ASC order, not id-DESC" do
      payload = handler_for("list videos sorted by title", channel: "@all").call.events.first[:payload]
      titles  = video_titles(payload)
      expect(titles).to eq([ "Alpha Sort Override Video", "Zebra Sort Override Video" ])
    end
  end

  # ── Channel threading ──────────────────────────────────────────────────────

  describe "channel: threading — backward compatibility" do
    it "constructs without channel: and works fine (default nil)" do
      h = described_class.new(
        message:      Pito::Chat::Message.new(tool: :list, body_tokens: [], kind: :new_turn, raw: "list games"),
        conversation: Conversation.singleton
      )
      expect { h.call }.not_to raise_error
    end

    it "exposes channel via attr_reader" do
      h = described_class.new(
        message:      Pito::Chat::Message.new(tool: :list, body_tokens: [], kind: :new_turn, raw: "list games"),
        conversation: Conversation.singleton,
        channel:      "@beta"
      )
      expect(h.channel).to eq("@beta")
    end
  end

  # ── Fuzzy noun correction ─────────────────────────────────────────────────────

  describe "fuzzy noun detection and correction notes" do
    let!(:game) { create(:game, title: "Hollow Knight") }
    let!(:connection) { create(:youtube_connection) }
    let!(:vid_channel) { create(:channel, handle: "@pito", youtube_connection: connection) }

    context "'list gamez' — exact synonym, no correction note" do
      # "gamez" is a synonym of "games" in NOUNS vocab → resolved by #resolve,
      # not fuzzy → no correction note.
      it "routes to the games path without a correction note" do
        result = handler_for("list gamez").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
        first_event = result.events.first
        text = first_event[:payload]["text"].to_s
        expect(text).not_to match(/gamez/i)
      end
    end

    context "'list gams' — fuzzy match to 'games' (dist 1 via synonym key 'game')" do
      # "gams" (4 chars, threshold 1): dist("gams","game") = 1 (synonym key) → "games"
      it "routes to the games path" do
        result = handler_for("list gams").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
      end

      it "prepends a correction note event" do
        result = handler_for("list gams").call
        note = result.events.first
        expect(note[:kind]).to eq(:system)
        text = note[:payload]["text"].to_s
        expect(text).to include("gams")
        expect(text).to include("games")
      end
    end

    context "'list chanels' — fuzzy match to 'channels' (dist 1, len 7)" do
      # "chanels" (7 chars, threshold 2): dist("chanels","channels") = 1
      it "routes to the channels path" do
        result = handler_for("list chanels").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
      end

      it "prepends a correction note event" do
        result = handler_for("list chanels").call
        note = result.events.first
        expect(note[:kind]).to eq(:system)
        text = note[:payload]["text"].to_s
        expect(text).to include("chanels")
        expect(text).to include("channels")
      end
    end

    context "'list vds' — fuzzy match to 'vids' (dist 1, len 3)" do
      # "vds" (3 chars, threshold 1): dist("vds","vids") = 1 (missing 'i')
      it "routes to the vids path" do
        create(:video, channel: vid_channel, title: "A Game")
        result = handler_for("list vds").call
        expect(result).to be_a(Pito::Chat::Result::Ok)
      end

      it "prepends a correction note event" do
        create(:video, channel: vid_channel, title: "A Game")
        result = handler_for("list vds").call
        note = result.events.first
        expect(note[:kind]).to eq(:system)
        text = note[:payload]["text"].to_s
        expect(text).to include("vds")
        expect(text).to include("vids")
      end
    end
  end

  # ── Capped list totals (list_more renders count + total) ─────────────────────
  #
  # All three surfaces load the full result into memory before paginating, so
  # the total is an O(1) array-size read — no extra DB queries.  These specs
  # stub page_size to 2 so we can use tiny fixtures.

  describe "capped list — count + total in list_footer" do
    let(:pager_stub) { { page_size: 2, more_tool: "next" } }

    before do
      allow(Pito::Dispatch::Config).to receive(:pager)
        .with(tool: :list)
        .and_return(pager_stub)
    end

    describe "games: 3 games, page_size=2" do
      let!(:g1) { create(:game, title: "Alpha") }
      let!(:g2) { create(:game, title: "Beta") }
      let!(:g3) { create(:game, title: "Gamma") }

      it "list_footer contains count (2) and total (3)" do
        payload = handler_for("list games").call.events.first[:payload]
        footer  = payload["list_footer"].to_s
        # Variant 0 of the new dictionary: "%{count} rows out of %{total}. `%{tool}` for more."
        expect(footer).to include("2")
        expect(footer).to include("3")
      end

      it "list_cursor is stamped on the payload" do
        payload = handler_for("list games").call.events.first[:payload]
        expect(payload["list_cursor"]).to be_a(Hash)
        expect(payload["list_cursor"]["offset"]).to eq(2)
      end
    end

    describe "videos: 3 videos, page_size=2" do
      let!(:chan) { create(:channel, handle: "@vc") }
      let!(:v1)   { create(:video, :public, title: "Vid A", channel: chan) }
      let!(:v2)   { create(:video, :public, title: "Vid B", channel: chan) }
      let!(:v3)   { create(:video, :public, title: "Vid C", channel: chan) }

      it "list_footer contains count (2) and total (3)" do
        payload = handler_for("list vids").call.events.first[:payload]
        footer  = payload["list_footer"].to_s
        expect(footer).to include("2")
        expect(footer).to include("3")
      end
    end

    describe "channels: 3 connected channels, page_size=2" do
      # The default :channel factory includes a youtube_connection.
      let!(:c1) { create(:channel, handle: "@ch1") }
      let!(:c2) { create(:channel, handle: "@ch2") }
      let!(:c3) { create(:channel, handle: "@ch3") }

      it "list_footer contains count (2) and total (3)" do
        payload = handler_for("list channels").call.events.first[:payload]
        footer  = payload["list_footer"].to_s
        expect(footer).to include("2")
        expect(footer).to include("3")
      end
    end
  end
end
