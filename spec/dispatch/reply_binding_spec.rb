# frozen_string_literal: true

require "rails_helper"

# Unit spec for Pito::Dispatch::ReplyBinding — the T8.7 declarative consumption
# seam that reads a verb's reply.targets.<target>.ref/args paths from the real
# config/pito/verbs.yml and runs each named resolver via Pito::Dispatch::Resolvers.
#
# Real config, real resolvers, real records (FactoryBot, transactional). The
# source event is a minimal Struct stand-in — only #payload matters. Because the
# binding resolves DB-backed refs, this leans on the same fixtures the resolver
# spec uses.
RSpec.describe Pito::Dispatch::ReplyBinding, type: :dispatch do
  before(:all) { Pito::Dispatch::Config.reload! }

  # A minimal source event: the binding + resolvers only call #payload.
  def source(payload) = Struct.new(:payload).new(payload)

  # Convenience.
  def bind(verb:, target:, rest:, source_event:)
    described_class.bind(verb:, target:, rest:, source_event:, conversation: nil)
  end

  # ══ 1. MECHANICS — no-op / empty Results ══════════════════════════════════════

  describe "targets with nothing to bind" do
    it "returns an empty, ok Result for an unknown verb" do
      result = bind(verb: "nonsense_verb", target: "video_list", rest: "5", source_event: source({}))
      expect(result.kwargs).to eq({})
      expect(result).to be_ok
    end

    it "returns an empty, ok Result when the verb has no reply branch" do
      # `import` is a chat-only verb — no reply.targets.
      result = bind(verb: "import", target: "game_list", rest: "x", source_event: source({}))
      expect(result.kwargs).to eq({})
      expect(result).to be_ok
    end

    it "returns an empty, ok Result when the target is not declared for the verb" do
      # `show` has a reply branch, but not a `bogus_target`.
      result = bind(verb: "show", target: "bogus_target", rest: "5", source_event: source({}))
      expect(result.kwargs).to eq({})
      expect(result).to be_ok
    end

    it "returns an empty, ok Result for a mode-only target (analyze/game_detail)" do
      # analyze's game_detail reply declares only a mode — no ref/args to bind.
      result = bind(verb: "analyze", target: "game_detail", rest: "", source_event: source({}))
      expect(result.kwargs).to eq({})
      expect(result).to be_ok
    end
  end

  # ══ 2. REF RESOLVERS ══════════════════════════════════════════════════════════

  describe "ref: id_among_rows (list targets, scoped to the source rows)" do
    let(:game) { create(:game) }
    let(:rows_source) do
      source({ "reply_target" => "game_list",
               "table_rows"   => [ { "cells" => [ { "text" => "##{game.id}" } ] } ] })
    end

    it "resolves `show <id>` to the row's game" do
      result = bind(verb: "show", target: "game_list", rest: game.id.to_s, source_event: rows_source)
      expect(result).to be_ok
      expect(result.kwargs[:ref]).to eq(game)
    end

    it "propagates Invalid (slot :ref) when the id is not among the source rows" do
      other  = create(:game)
      result = bind(verb: "show", target: "game_list", rest: other.id.to_s, source_event: rows_source)
      expect(result).not_to be_ok
      expect(result.kwargs).to eq({})
      expect(result.invalid).to be_a(Pito::Dispatch::ReplyBinding::BoundInvalid)
      expect(result.invalid.slot).to eq(:ref)
      expect(result.invalid.resolver).to eq("id_among_rows")
      expect(result.invalid.reason).to match(/not in the source list/)
    end
  end

  describe "ref: channel_by_handle (@handle from the reply args)" do
    it "resolves `shinies @handle` to that channel" do
      channel = create(:channel, handle: "gmrdad82")
      result  = bind(verb: "shinies", target: "channel_list", rest: "@gmrdad82", source_event: source({}))
      expect(result).to be_ok
      expect(result.kwargs[:ref]).to eq(channel)
    end
  end

  describe "ref: source_entity (detail card entity from the payload id_key)" do
    it "resolves `reindex` on game_detail from payload game_id (input ignored)" do
      game   = create(:game)
      result = bind(verb: "reindex", target: "game_detail", rest: "", source_event: source({ "game_id" => game.id }))
      expect(result).to be_ok
      expect(result.kwargs[:ref]).to eq(game)
    end

    it "resolves `sync` on channel_detail from payload channel_id" do
      channel = create(:channel)
      result  = bind(verb: "sync", target: "channel_detail", rest: "", source_event: source({ "channel_id" => channel.id }))
      expect(result).to be_ok
      expect(result.kwargs[:ref]).to eq(channel)
    end
  end

  describe "ref: entity finders on rendered-strip show targets" do
    it "game_similar `show <id>` → game_by_id" do
      game   = create(:game)
      result = bind(verb: "show", target: "game_similar", rest: game.id.to_s, source_event: source({}))
      expect(result.kwargs[:ref]).to eq(game)
    end

    it "game_linked_videos `show <id>` → video_by_id" do
      video  = create(:video)
      result = bind(verb: "show", target: "game_linked_videos", rest: "##{video.id}", source_event: source({}))
      expect(result.kwargs[:ref]).to eq(video)
    end
  end

  # ══ 3. ARG RESOLVERS ══════════════════════════════════════════════════════════

  describe "args (clause scanners get the FULL '<verb> <rest>' command)" do
    it "sort/video_list → sort_clause parses `by views desc`" do
      result = bind(verb: "sort", target: "video_list", rest: "by views desc", source_event: source({}))
      expect(result).to be_ok
      expect(result.kwargs[:clause]).to eq({ token: "views", direction: :desc })
    end

    it "with/video_list → column_list parses against the video column vocabulary" do
      result = bind(verb: "with", target: "video_list", rest: "views, likes", source_event: source({}))
      expect(result).to be_ok
      expect(result.kwargs[:columns]).to include(:views, :likes)
    end

    it "with/analyze_message → metric_list yields a Selection" do
      result = bind(verb: "with", target: "analyze_message", rest: "views, subs", source_event: source({}))
      expect(result).to be_ok
      expect(result.kwargs[:metrics]).to be_a(Pito::Analytics::MetricSelection::Selection)
      expect(result.kwargs[:metrics].with).to include(:views, :subs)
    end
  end

  describe "args (word / when-phrase get the bare reply args)" do
    it "visit/channel_detail resolves BOTH the source channel (ref) and the destination (arg)" do
      channel = create(:channel)
      result  = bind(verb: "visit", target: "channel_detail", rest: "studio",
                     source_event: source({ "channel_id" => channel.id }))
      expect(result).to be_ok
      expect(result.kwargs[:ref]).to eq(channel)
      expect(result.kwargs[:destination]).to eq("studio")
    end

    it "schedule/video_detail resolves the source video (ref) and the when-phrase (arg)" do
      video  = create(:video)
      result = bind(verb: "schedule", target: "video_detail", rest: "in 30m",
                    source_event: source({ "video_id" => video.id }))
      expect(result).to be_ok
      expect(result.kwargs[:ref]).to eq(video)
      expect(result.kwargs[:when]).to be_a(ActiveSupport::TimeWithZone).or be_a(Time)
    end
  end

  # ══ 4. INVALID PROPAGATION (first failing slot short-circuits) ═════════════════

  describe "Invalid propagation" do
    it "an arg Invalid stops with slot naming the arg (visit bad destination)" do
      channel = create(:channel)
      result  = bind(verb: "visit", target: "channel_detail", rest: "twitch",
                     source_event: source({ "channel_id" => channel.id }))
      expect(result).not_to be_ok
      expect(result.kwargs).to eq({})
      expect(result.invalid.slot).to eq(:destination)
      expect(result.invalid.resolver).to eq("visit_destination")
      expect(result.invalid.reason).to match(/unknown visit destination/)
    end

    it "a ref Invalid short-circuits BEFORE the arg is resolved (visit, missing channel)" do
      result = bind(verb: "visit", target: "channel_detail", rest: "studio",
                    source_event: source({ "channel_id" => 9_999_999 }))
      expect(result).not_to be_ok
      expect(result.invalid.slot).to eq(:ref)
      expect(result.invalid.resolver).to eq("source_entity")
    end
  end

  # ══ 5. ALIAS CANONICALIZATION ═════════════════════════════════════════════════

  describe "verb aliases" do
    it "canonicalizes `rm` → delete before reading the reply-branch paths" do
      game = create(:game)
      rows = source({ "reply_target" => "game_list",
                      "table_rows"   => [ { "cells" => [ { "text" => "##{game.id}" } ] } ] })
      result = bind(verb: "rm", target: "game_list", rest: game.id.to_s, source_event: rows)
      expect(result).to be_ok
      expect(result.kwargs[:ref]).to eq(game)
    end
  end

  # ══ 6. T8.15 — the NARROWED cases (D10: no reply extraction left undeclared) ═══
  #
  # Each declared path must extract EXACTLY what the handler's own extraction
  # produces. The list `<id> <value>` shapes rely on the LEADING_TOKEN_REFS seam:
  # the row id is sliced from the leading token (→ ref), the value from the tail
  # (→ arg). Detail shapes leave the value on the full rest.

  # A game_list source stamping one row (id N) so id_among_rows scopes to it.
  def game_row(game) = source({ "reply_target" => "game_list", "table_rows" => [ { "cells" => [ { "text" => "##{game.id}" } ] } ] })
  def video_row(video) = source({ "reply_target" => "video_list", "table_rows" => [ { "cells" => [ { "text" => "##{video.id}" } ] } ] })

  describe "footage / game_detail — `footage [update] <hours>` amount" do
    let(:game) { create(:game) }
    let(:card) { source({ "reply_target" => "game_detail", "game_id" => game.id }) }

    it "resolves the source game (ref) and the ceil'd half-step hours (arg)" do
      result = bind(verb: "footage", target: "game_detail", rest: "update 12.5", source_event: card)
      expect(result).to be_ok
      expect(result.kwargs[:ref]).to eq(game)
      expect(result.kwargs[:hours]).to eq(Pito::Games::FootageAmount.parse("update 12.5")).and eq(25r / 2)
    end

    it "malformed: a non-numeric amount short-circuits with slot :hours" do
      result = bind(verb: "footage", target: "game_detail", rest: "lots", source_event: card)
      expect(result).not_to be_ok
      expect(result.invalid.slot).to eq(:hours)
      expect(result.invalid.resolver).to eq("footage_hours")
    end
  end

  describe "price — `price [set] <amount>` / `price unset`" do
    let(:game) { create(:game) }
    let(:card) { source({ "reply_target" => "game_detail", "game_id" => game.id }) }

    it "detail: resolves the source game and a 2dp BigDecimal amount" do
      result = bind(verb: "price", target: "game_detail", rest: "set 9.99", source_event: card)
      expect(result).to be_ok
      expect(result.kwargs[:ref]).to eq(game)
      expect(result.kwargs[:amount]).to eq(BigDecimal("9.99"))
    end

    it "detail: `unset` binds the :unset sentinel" do
      result = bind(verb: "price", target: "game_detail", rest: "unset", source_event: card)
      expect(result.kwargs[:amount]).to eq(:unset)
    end

    it "list: the leading row id is sliced to the ref, the amount to the arg" do
      result = bind(verb: "price", target: "game_list", rest: "#{game.id} 9.99", source_event: game_row(game))
      expect(result).to be_ok
      expect(result.kwargs[:ref]).to eq(game)
      expect(result.kwargs[:amount]).to eq(BigDecimal("9.99"))
    end

    it "malformed: a non-numeric amount short-circuits with slot :amount" do
      result = bind(verb: "price", target: "game_detail", rest: "free", source_event: card)
      expect(result).not_to be_ok
      expect(result.invalid.slot).to eq(:amount)
    end
  end

  describe "platform — `platform [set|unset] <value>`" do
    let(:game) { create(:game) }
    let(:card) { source({ "reply_target" => "game_detail", "game_id" => game.id }) }

    it "detail: resolves the source game and the canonical platform value" do
      result = bind(verb: "platform", target: "game_detail", rest: "set ps5", source_event: card)
      expect(result).to be_ok
      expect(result.kwargs[:ref]).to eq(game)
      expect(result.kwargs[:value]).to eq("PlayStation 5")
    end

    it "list: the leading row id is sliced to the ref, the value to the arg" do
      result = bind(verb: "platform", target: "game_list", rest: "#{game.id} switch", source_event: game_row(game))
      expect(result).to be_ok
      expect(result.kwargs[:ref]).to eq(game)
      expect(result.kwargs[:value]).to eq("Nintendo Switch")
    end

    it "malformed: a blank value short-circuits with slot :value" do
      result = bind(verb: "platform", target: "game_detail", rest: "set", source_event: card)
      expect(result).not_to be_ok
      expect(result.invalid.slot).to eq(:value)
    end
  end

  describe "schedule / video_list — `<id> <when>` interleave (D10 seam)" do
    let(:video) { create(:video) }

    it "slices the row id to id_among_rows and the when-phrase to schedule_expression" do
      result = bind(verb: "schedule", target: "video_list", rest: "#{video.id} in 30m", source_event: video_row(video))
      expect(result).to be_ok
      expect(result.kwargs[:ref]).to eq(video)
      expect(result.kwargs[:when]).to be_a(ActiveSupport::TimeWithZone).or be_a(Time)
    end

    it "malformed: an unrecognized when-phrase short-circuits with slot :when" do
      result = bind(verb: "schedule", target: "video_list", rest: "#{video.id} whenever", source_event: video_row(video))
      expect(result).not_to be_ok
      expect(result.invalid.slot).to eq(:when)
    end
  end

  describe "link / unlink — dual-ref (source + target list)" do
    let(:game)  { create(:game) }
    let(:video) { create(:video) }

    it "link/game_detail: source game from payload, target video(s) after the connector" do
      card   = source({ "reply_target" => "game_detail", "game_id" => game.id })
      result = bind(verb: "link", target: "game_detail", rest: "to video #{video.id}", source_event: card)
      expect(result).to be_ok
      expect(result.kwargs[:ref]).to eq(game)
      expect(result.kwargs[:linked_ref]).to eq([ video ])
    end

    it "link/game_list: source id LEFT of the connector, target video RIGHT" do
      result = bind(verb: "link", target: "game_list", rest: "#{game.id} to #{video.id}", source_event: game_row(game))
      expect(result).to be_ok
      expect(result.kwargs[:ref]).to eq(game)
      expect(result.kwargs[:linked_ref]).to eq([ video ])
    end

    it "link/video_list: reply_target `video*` flips source→Video, target→Game" do
      result = bind(verb: "link", target: "video_list", rest: "#{video.id} to #{game.id}", source_event: video_row(video))
      expect(result).to be_ok
      expect(result.kwargs[:ref]).to eq(video)
      expect(result.kwargs[:linked_ref]).to eq([ game ])
    end

    it "unlink/game_linked_videos: SOURCE is the parent Game (payload game_id), TARGET the typed video" do
      card   = source({ "reply_target" => "game_linked_videos", "game_id" => game.id, "video_ids" => [ video.id ] })
      result = bind(verb: "unlink", target: "game_linked_videos", rest: video.id.to_s, source_event: card)
      expect(result).to be_ok
      expect(result.kwargs[:ref]).to eq(game)
      expect(result.kwargs[:linked_ref]).to eq([ video ])
    end

    it "missing target: an unresolvable target id short-circuits with slot :linked_ref" do
      card   = source({ "reply_target" => "game_detail", "game_id" => game.id })
      result = bind(verb: "link", target: "game_detail", rest: "to 9999999", source_event: card)
      expect(result).not_to be_ok
      expect(result.invalid.slot).to eq(:linked_ref)
      expect(result.invalid.resolver).to eq("link_targets")
    end
  end
end
