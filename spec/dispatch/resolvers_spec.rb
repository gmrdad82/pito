# frozen_string_literal: true

require "rails_helper"

# Unit spec for Pito::Dispatch::Resolvers — the §5 resolver registry.
#
# Three concerns:
#   1. REGISTRY MECHANICS — register/resolve/registered?/names API + error paths.
#   2. ADAPTER CONTRACTS  — happy path and invalid path for each registered adapter.
#      DB-backed adapters (game_by_id, video_by_id, channel_by_handle, id_among_rows)
#      use real records via FactoryBot (transactional fixtures roll them back).
#      In-memory adapters use the real collaborator modules — no mocks.
#   3. INTEGRITY          — every resolver: name used in ref/args positions of
#      tools.yml is registered in the live registry, closing the loop the schema
#      suite previously stubbed out with a hard-coded allow-list.
RSpec.describe Pito::Dispatch::Resolvers, type: :dispatch do
  # Shorthand
  let(:invalid_class) { Pito::Dispatch::Resolvers::Invalid }

  # ══ 1. REGISTRY MECHANICS ════════════════════════════════════════════════════

  describe "registry mechanics" do
    it "registered? returns true for a registered name" do
      expect(described_class.registered?(:sort_clause)).to be(true)
    end

    it "registered? returns false for an unknown name" do
      expect(described_class.registered?(:no_such_resolver)).to be(false)
    end

    it "resolve raises KeyError for an unknown name" do
      expect { described_class.resolve(:no_such_resolver, "foo") }
        .to raise_error(KeyError, /unknown resolver: :no_such_resolver/)
    end

    it "names returns a sorted, frozen Array of Symbols" do
      n = described_class.names
      expect(n).to be_an(Array)
      expect(n).to be_frozen
      expect(n).to eq(n.sort)
      expect(n).to all(be_a(Symbol))
    end

    it "names includes all expected resolver names" do
      expect(described_class.names).to include(
        :channel_by_handle, :video_by_id, :game_by_id, :id_among_rows,
        :schedule_expression, :column_list, :sort_clause, :metric_list,
        :game_titles, :visit_destination, :source_entity,
        :link_source, :link_targets
      )
    end
  end

  # ══ 2. ADAPTER CONTRACTS ══════════════════════════════════════════════════════

  # ── :channel_by_handle ───────────────────────────────────────────────────────

  describe ":channel_by_handle" do
    it "happy: resolves a @handle string to the matching Channel" do
      channel = create(:channel, handle: "testchannel")
      result  = described_class.resolve(:channel_by_handle, "@testchannel")
      expect(result).to eq(channel)
    end

    it "invalid: returns Invalid when the channel does not exist" do
      result = described_class.resolve(:channel_by_handle, "@ghost_channel_xyzzy")
      expect(result).to be_a(invalid_class)
      expect(result.reason).to match(/channel not found/)
    end

    it "fuzzy: resolves a partial handle to the nearest Channel (#7)" do
      channel = create(:channel, handle: "@fighterpro")
      result  = described_class.resolve(:channel_by_handle, "fighter")
      expect(result).to eq(channel)
    end
  end

  # ── :video_by_id ─────────────────────────────────────────────────────────────

  describe ":video_by_id" do
    it "happy: resolves a #N string to the matching Video" do
      video  = create(:video)
      result = described_class.resolve(:video_by_id, "##{video.id}")
      expect(result).to eq(video)
    end

    it "invalid: returns Invalid when the video does not exist" do
      result = described_class.resolve(:video_by_id, "#9999999")
      expect(result).to be_a(invalid_class)
      expect(result.reason).to match(/video not found/)
    end
  end

  # ── :game_by_id ──────────────────────────────────────────────────────────────

  describe ":game_by_id" do
    it "happy: resolves a plain N string to the matching Game" do
      game   = create(:game)
      result = described_class.resolve(:game_by_id, game.id.to_s)
      expect(result).to eq(game)
    end

    it "invalid: returns Invalid when the game does not exist" do
      result = described_class.resolve(:game_by_id, "9999999")
      expect(result).to be_a(invalid_class)
      expect(result.reason).to match(/game not found/)
    end
  end

  # ── :id_among_rows ───────────────────────────────────────────────────────────

  describe ":id_among_rows" do
    let(:game) { create(:game) }

    # A minimal stand-in for the source event: only the .payload method matters.
    let(:source_with_game) do
      payload = { table_rows: [ { cells: [ { text: "##{game.id}" } ] } ] }
      Struct.new(:payload).new(payload)
    end

    let(:source_without_game) do
      payload = { table_rows: [ { cells: [ { text: "#9999999" } ] } ] }
      Struct.new(:payload).new(payload)
    end

    it "happy: returns the record when the id is among the source rows" do
      result = described_class.resolve(
        :id_among_rows,
        game.id.to_s,
        context: { entity_class: ::Game, source_event: source_with_game }
      )
      expect(result).to eq(game)
    end

    it "invalid: returns Invalid when the record is not in the source rows" do
      result = described_class.resolve(
        :id_among_rows,
        game.id.to_s,
        context: { entity_class: ::Game, source_event: source_without_game }
      )
      expect(result).to be_a(invalid_class)
      expect(result.reason).to match(/not in the source list/)
    end
  end

  # ── :schedule_expression ─────────────────────────────────────────────────────

  describe ":schedule_expression" do
    let(:now) { Time.zone.local(2026, 7, 3, 12, 0, 0) }

    it "happy: parses 'in 30m' to a Time 30 minutes from now" do
      result = described_class.resolve(:schedule_expression, "in 30m", context: { now: })
      expect(result).to be_a(ActiveSupport::TimeWithZone).or be_a(Time)
      expect(result).to be_within(5.seconds).of(now + 30.minutes)
    end

    it "invalid: returns Invalid for unrecognized input" do
      result = described_class.resolve(:schedule_expression, "whenever", context: { now: })
      expect(result).to be_a(invalid_class)
      expect(result.reason).to match(/unrecognized schedule expression/)
    end
  end

  # ── :column_list ─────────────────────────────────────────────────────────────

  describe ":column_list" do
    # Use the real game-list column vocabulary — the one the list handler uses.
    let(:vocab) { Pito::MessageBuilder::Game::ListColumns.vocabulary }

    it "happy: parses 'with platform, genre' against the game-list vocabulary" do
      result = described_class.resolve(
        :column_list,
        "list games with platform, genre",
        context: { vocabulary: vocab }
      )
      expect(result).to include(:platform, :genre)
    end

    it "invalid: returns Invalid when the with-clause names no recognized columns" do
      result = described_class.resolve(
        :column_list,
        "list games with unknowncol_xyzzy",
        context: { vocabulary: vocab }
      )
      expect(result).to be_a(invalid_class)
      expect(result.reason).to match(/no recognized columns/)
    end
  end

  # ── :sort_clause ─────────────────────────────────────────────────────────────

  describe ":sort_clause" do
    it "happy: parses 'list games sorted by price desc' to a sort hash" do
      result = described_class.resolve(:sort_clause, "list games sorted by price desc")
      expect(result).to eq({ token: "price", direction: :desc })
    end

    it "invalid: returns Invalid when no sort clause is present" do
      result = described_class.resolve(:sort_clause, "list games")
      expect(result).to be_a(invalid_class)
      expect(result.reason).to match(/no sort clause/)
    end
  end

  # ── :metric_list ─────────────────────────────────────────────────────────────

  describe ":metric_list" do
    it "happy: parses 'with views, subs' to a Selection with those metrics" do
      result = described_class.resolve(:metric_list, "with views, subs")
      expect(result).to be_a(Pito::Analytics::MetricSelection::Selection)
      expect(result.with).to include(:views, :subs)
    end

    it "invalid: returns Invalid when no with/without clause is present" do
      result = described_class.resolve(:metric_list, "analyze vid #1")
      expect(result).to be_a(invalid_class)
      expect(result.reason).to match(/no metrics specified/)
    end
  end

  # ── :game_titles ─────────────────────────────────────────────────────────────

  describe ":game_titles" do
    it "happy: returns matching game titles for a given prefix" do
      create(:game, title: "Zelda Breath of the Wild")
      result = described_class.resolve(:game_titles, "Zelda")
      expect(result).to include("Zelda Breath of the Wild")
    end

    it "invalid: returns Invalid when no titles match the prefix" do
      result = described_class.resolve(:game_titles, "NoGameWithThisPrefix_xyzzy")
      expect(result).to be_a(invalid_class)
      expect(result.reason).to match(/no game titles matched/)
    end
  end

  # ── :visit_destination ───────────────────────────────────────────────────────

  describe ":visit_destination" do
    it "happy: resolves 'studio' to the canonical destination string" do
      result = described_class.resolve(:visit_destination, "studio")
      expect(result).to eq("studio")
    end

    it "happy: resolves the 'yt' synonym to 'channel'" do
      result = described_class.resolve(:visit_destination, "yt")
      expect(result).to eq("channel")
    end

    it "invalid: returns Invalid for an unknown destination" do
      result = described_class.resolve(:visit_destination, "twitch")
      expect(result).to be_a(invalid_class)
      expect(result.reason).to match(/unknown visit destination/)
    end
  end

  # ── :source_entity ───────────────────────────────────────────────────────────

  describe ":source_entity" do
    # Minimal stand-in for the source event: only #payload matters.
    def source_event_with(payload)
      Struct.new(:payload).new(payload)
    end

    it "happy: resolves the entity from the source event's payload id_key" do
      game   = create(:game)
      source = source_event_with({ game_id: game.id })
      result = described_class.resolve(
        :source_entity, nil,
        context: { entity_class: ::Game, id_key: :game_id, source_event: source }
      )
      expect(result).to eq(game)
    end

    it "ignores the input token (the id lives in the event, not the typed reply)" do
      video  = create(:video)
      source = source_event_with({ video_id: video.id })
      result = described_class.resolve(
        :source_entity, "ignored-typed-text",
        context: { entity_class: ::Video, id_key: :video_id, source_event: source }
      )
      expect(result).to eq(video)
    end

    it "invalid: returns Invalid when the payload carries no id" do
      source = source_event_with({ "other" => 1 })
      result = described_class.resolve(
        :source_entity, nil,
        context: { entity_class: ::Game, id_key: :game_id, source_event: source }
      )
      expect(result).to be_a(invalid_class)
      expect(result.reason).to match(/source event has no game_id/)
    end

    it "invalid: returns Invalid when the id does not resolve to a record" do
      source = source_event_with({ game_id: 9_999_999 })
      result = described_class.resolve(
        :source_entity, nil,
        context: { entity_class: ::Game, id_key: :game_id, source_event: source }
      )
      expect(result).to be_a(invalid_class)
      expect(result.reason).to match(/Game not found/)
    end

    it "invalid: returns Invalid when required context keys are missing" do
      result = described_class.resolve(:source_entity, nil, context: {})
      expect(result).to be_a(invalid_class)
      expect(result.reason).to match(/entity_class/)
    end
  end

  # ── :link_source / :link_targets (T8.15 — dual-ref, from reply_target) ────────

  describe ":link_source" do
    let(:game)  { create(:game) }
    let(:video) { create(:video) }

    def source_event(payload) = Struct.new(:payload).new(payload)

    it "detail: resolves the SOURCE game from the payload game_id (game_detail)" do
      ev = source_event({ reply_target: "game_detail", game_id: game.id })
      result = described_class.resolve(:link_source, "to #{video.id}", context: { source_event: ev })
      expect(result).to eq(game)
    end

    it "detail: game_linked_videos resolves its SOURCE as the parent Game (game_id)" do
      ev = source_event({ reply_target: "game_linked_videos", game_id: game.id, video_ids: [ video.id ] })
      result = described_class.resolve(:link_source, "#{video.id}", context: { source_event: ev })
      expect(result).to eq(game)
    end

    it "list: resolves the SOURCE from the id LEFT of the connector (game_list)" do
      ev = source_event({ reply_target: "game_list" })
      result = described_class.resolve(:link_source, "#{game.id} to #{video.id}", context: { source_event: ev })
      expect(result).to eq(game)
    end

    it "list: video_list source is a Video (reply_target starts with `video`)" do
      ev = source_event({ reply_target: "video_list" })
      result = described_class.resolve(:link_source, "#{video.id} to #{game.id}", context: { source_event: ev })
      expect(result).to eq(video)
    end

    it "invalid: a missing source record resolves Invalid" do
      ev = source_event({ reply_target: "game_list" })
      result = described_class.resolve(:link_source, "9999999 to 1", context: { source_event: ev })
      expect(result).to be_a(invalid_class)
    end

    it "list: a single-row card's game_ids implies the source when no id is typed" do
      ev = source_event({ reply_target: "game_list", game_ids: [ game.id ] })
      result = described_class.resolve(:link_source, "to #{video.id}", context: { source_event: ev })
      expect(result).to eq(game)
    end

    it "list: a typed numeric left id wins over a single-row card's implied source" do
      other_game = create(:game)
      ev = source_event({ reply_target: "game_list", game_ids: [ game.id ] })
      result = described_class.resolve(:link_source, "#{other_game.id} to #{video.id}", context: { source_event: ev })
      expect(result).to eq(other_game)
    end

    it "list: two rows in the card resolves Invalid (no implied source)" do
      g2 = create(:game)
      ev = source_event({ reply_target: "game_list", game_ids: [ game.id, g2.id ] })
      result = described_class.resolve(:link_source, "to #{video.id}", context: { source_event: ev })
      expect(result).to be_a(invalid_class)
    end
  end

  describe ":link_targets" do
    let(:game)  { create(:game) }
    let(:video) { create(:video) }

    def source_event(payload) = Struct.new(:payload).new(payload)

    it "resolves the TARGET video(s) after the connector (game source → video targets)" do
      ev = source_event({ reply_target: "game_list" })
      result = described_class.resolve(:link_targets, "#{game.id} to #{video.id}", context: { source_event: ev })
      expect(result).to eq([ video ])
    end

    it "resolves a comma/space id LIST of targets" do
      v2 = create(:video)
      ev = source_event({ reply_target: "game_detail", game_id: game.id })
      result = described_class.resolve(:link_targets, "to #{video.id},#{v2.id}", context: { source_event: ev })
      expect(result).to contain_exactly(video, v2)
    end

    it "video source → game targets (reply_target starts with `video`)" do
      ev = source_event({ reply_target: "video_list" })
      result = described_class.resolve(:link_targets, "#{video.id} to #{game.id}", context: { source_event: ev })
      expect(result).to eq([ game ])
    end

    it "no-connector detail reply strips a leading noun (game_linked_videos)" do
      ev = source_event({ reply_target: "game_linked_videos", game_id: game.id, video_ids: [ video.id ] })
      result = described_class.resolve(:link_targets, "video #{video.id}", context: { source_event: ev })
      expect(result).to eq([ video ])
    end

    it "invalid: no numeric id resolves Invalid" do
      ev = source_event({ reply_target: "game_list" })
      result = described_class.resolve(:link_targets, "#{game.id} to nothing", context: { source_event: ev })
      expect(result).to be_a(invalid_class)
    end

    it "invalid: all target ids missing resolves Invalid (mirrors all-not-found)" do
      ev = source_event({ reply_target: "game_list" })
      result = described_class.resolve(:link_targets, "#{game.id} to 9999999", context: { source_event: ev })
      expect(result).to be_a(invalid_class)
    end
  end

  # ══ 3. INTEGRITY ════════════════════════════════════════════════════════════
  #
  # Every resolver: name used in ref/args positions in tools.yml must be
  # registered in the live Resolvers registry. This closes the loop that the
  # schema-integrity suite previously covered with a hard-coded RESOLVERS
  # constant (now derived from the registry itself).

  describe "integrity" do
    before(:all) { Pito::Dispatch::Config.reload! }

    it "every resolver: name in tools.yml ref/args positions is registered" do
      doc   = Pito::Dispatch::Config.data
      verbs = doc[:tools]

      used_names = verbs.flat_map do |_verb, body|
        Array(body.dig(:reply, :targets)&.values).flat_map do |target|
          refs = Array(target[:ref]&.values)
          args = Array(target[:args]&.values).flat_map { |a| Array(a&.values) }
          refs + args
        end
      end.compact.uniq

      unregistered = used_names.reject { |name| described_class.registered?(name.to_sym) }
      expect(unregistered).to(
        eq([]),
        -> { "These resolver names appear in tools.yml but are not registered: #{unregistered.inspect}" }
      )
    end
  end
end
