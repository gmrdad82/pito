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

    it "returns an empty, ok Result for a NARROWED target that declares no ref/args (link)" do
      result = bind(verb: "link", target: "video_list", rest: "10 to 5", source_event: source({}))
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
end
