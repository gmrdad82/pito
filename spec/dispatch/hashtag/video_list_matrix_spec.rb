# frozen_string_literal: true

require "rails_helper"

# ── Exhaustive recognition matrix: `video_list` hashtag follow-up ──────────────
#
# RULE: every action + arg combination recognised — no exception.
# Tests what the handler ROUTES, not what it executes.
# Zero factories: source event via plain double; all DB mocked.
#
# Routing map:
#   with / without           → mutate_columns  → Result::Mutation (in-place re-render)
#   sort / order             → mutate_sort     → Result::Mutation (in-place re-sort)
#   show / delete / del / rm /
#   schedule / publish / pub /
#   unlist / link / unlink / shinies → ToolDelegator → Result::Append (sentinel)
#   unknown verb             → ToolDelegator gates → Result::Error
#
# ToolDelegator is stubbed to a sentinel for delegated-action paths.
# For the unknown-action paths ToolDelegator is let run for real (gating check
# is pure: registry lookup only, no DB, no Chat::Dispatcher invocation).
#
# A declared action that returns invalid_action Error = BUG — reported verbatim.
RSpec.describe "Dispatch matrix — #video_list follow-up (recognition, DB mocked)", type: :dispatch do
  before(:all) { Pito::FollowUp::Registry.register_all! }

  let(:handler)      { Pito::FollowUp::Handlers::VideoList.new }
  let(:conversation) { double("Conversation") }

  # Sentinel returned by ToolDelegator for every delegated action.
  let(:sentinel) { Pito::FollowUp::Result::Append.new(events: [], consume: true) }

  # Source event: video_list with 2 stamped ids and two extra columns (channel, views).
  # No factories — entirely in-memory.
  let(:source_event) do
    double("Event",
      kind:    "system",
      payload: {
        "reply_target" => "video_list",
        "reply_handle" => "abc123",
        "video_ids"    => [ 10, 20 ],
        "list_columns" => %w[channel views],
        "table_rows"   => []
      }
    )
  end

  # Convenience: invoke the handler with a rest string.
  def call(rest)
    handler.call(event: source_event, rest:, conversation:)
  end

  # ── Global stubs ─────────────────────────────────────────────────────────────
  before do
    # ToolDelegator → sentinel for all delegated-action paths (overridden for unknowns).
    allow(Pito::FollowUp::ToolDelegator).to receive(:call).and_return(sentinel)

    # DB: Video.where(id: [10, 20]) → 2 plain doubles ordered by stamped position.
    v1 = double(:video, id: 10)
    v2 = double(:video, id: 20)
    allow(::Video).to receive(:where).and_return([ v1, v2 ])

    # List builder → minimal mutable Hash (mutate_ methods modify it with reply_handle etc.).
    allow(Pito::MessageBuilder::Video::List).to receive(:call).and_return(
      { "table_rows" => [], "list_columns" => %w[channel views] }
    )

    # sort_key_for → nil so video doubles need no attribute stubs.
    # The sort is a lenient no-op when the key is nil — still produces a Mutation.
    allow(Pito::MessageBuilder::Video::ListColumns).to receive(:sort_key_for).and_return(nil)
  end

  # ── Registry ─────────────────────────────────────────────────────────────────

  describe "Registry" do
    it "resolves 'video_list' to Handlers::VideoList" do
      expect(Pito::FollowUp::Registry.for("video_list"))
        .to eq(Pito::FollowUp::Handlers::VideoList)
    end

    it "default mode_for('video_list') is :append" do
      expect(Pito::FollowUp::Registry.mode_for("video_list")).to eq(:append)
    end

    it "mode_for('video_list', action: 'with') is :mutate" do
      expect(Pito::FollowUp::Registry.mode_for("video_list", action: "with")).to eq(:mutate)
    end

    it "mode_for('video_list', action: 'without') is :mutate" do
      expect(Pito::FollowUp::Registry.mode_for("video_list", action: "without")).to eq(:mutate)
    end

    it "mode_for('video_list', action: 'sort') is :mutate" do
      expect(Pito::FollowUp::Registry.mode_for("video_list", action: "sort")).to eq(:mutate)
    end

    it "mode_for('video_list', action: 'order') is :mutate" do
      expect(Pito::FollowUp::Registry.mode_for("video_list", action: "order")).to eq(:mutate)
    end

    it "actions_for('video_list') lists all 20 declared actions (G122/G123 add game + at-a-glance; more alias of next)" do
      expect(Pito::FollowUp::Registry.actions_for("video_list")).to match_array(
        %w[show delete del rm schedule publish pub unlist with without sort order link unlink shinies analyze next more game at-a-glance]
      )
    end

    it "target class declares 'video_list'" do
      expect(Pito::FollowUp::Handlers::VideoList.target).to eq("video_list")
    end

    it "Matrix serves :append base mode for video_list" do
      expect(Pito::Dispatch::Matrix.mode_for("video_list")).to eq(:append)
    end
  end

  # ── `with <column>` → Result::Mutation ───────────────────────────────────────
  #
  # Every alias from Pito::MessageBuilder::Video::ListColumns::COLUMNS.
  # Unknown aliases are a no-op (empty delta) but still produce a Mutation.

  describe "with <column> → Result::Mutation (column union, in-place re-render)" do
    {
      "channel"    => "COLUMNS[:channel] — primary alias",
      "status"     => "COLUMNS[:visibility] — alias 'status'",
      "visibility" => "COLUMNS[:visibility] — alias 'visibility'",
      "game"       => "COLUMNS[:game] — alias 'game'",
      "games"      => "COLUMNS[:game] — alias 'games'",
      "length"     => "COLUMNS[:duration] — alias 'length'",
      "duration"   => "COLUMNS[:duration] — alias 'duration'",
      "views"      => "COLUMNS[:views] — primary alias",
      "likes"      => "COLUMNS[:likes] — primary alias",
      "comms"      => "COLUMNS[:comments] — alias 'comms'",
      "comments"   => "COLUMNS[:comments] — alias 'comments'",
      "category"   => "COLUMNS[:category] — alias 'category'",
      "categories" => "COLUMNS[:category] — alias 'categories'"
    }.each do |token, note|
      it "with #{token.inspect} (#{note}) → Mutation" do
        expect(call("with #{token}")).to be_a(Pito::FollowUp::Result::Mutation)
      end
    end

    it "with views, likes (comma-separated two columns) → Mutation" do
      expect(call("with views, likes")).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "with channel, game, duration (three columns) → Mutation" do
      expect(call("with channel, game, duration")).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "with unknown_column (unrecognised alias) → Mutation (no-op delta, zero added)" do
      expect(call("with unknown_column")).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "Mutation kind reflects source event kind" do
      expect(call("with views").kind).to eq(:system)
    end

    it "Mutation payload does NOT carry surface (reply elevation removed)" do
      expect(call("with views").payload).not_to have_key("surface")
    end

    it "Mutation payload preserves reply_handle from source event" do
      expect(call("with views").payload["reply_handle"]).to eq("abc123")
    end

    it "Mutation payload preserves reply_target from source event" do
      expect(call("with views").payload["reply_target"]).to eq("video_list")
    end

    it "does NOT delegate to ToolDelegator" do
      call("with views")
      expect(Pito::FollowUp::ToolDelegator).not_to have_received(:call)
    end
  end

  # ── `without <column>` → Result::Mutation ────────────────────────────────────

  describe "without <column> → Result::Mutation (column difference, in-place re-render)" do
    {
      "channel"    => "COLUMNS[:channel] — primary alias",
      "status"     => "COLUMNS[:visibility] — alias 'status'",
      "visibility" => "COLUMNS[:visibility] — alias 'visibility'",
      "game"       => "COLUMNS[:game] — alias 'game'",
      "games"      => "COLUMNS[:game] — alias 'games'",
      "length"     => "COLUMNS[:duration] — alias 'length'",
      "duration"   => "COLUMNS[:duration] — alias 'duration'",
      "views"      => "COLUMNS[:views] — primary alias",
      "likes"      => "COLUMNS[:likes] — primary alias",
      "comms"      => "COLUMNS[:comments] — alias 'comms'",
      "comments"   => "COLUMNS[:comments] — alias 'comments'",
      "category"   => "COLUMNS[:category] — alias 'category'",
      "categories" => "COLUMNS[:category] — alias 'categories'"
    }.each do |token, note|
      it "without #{token.inspect} (#{note}) → Mutation" do
        expect(call("without #{token}")).to be_a(Pito::FollowUp::Result::Mutation)
      end
    end

    it "without views, likes (comma-separated two columns) → Mutation" do
      expect(call("without views, likes")).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "without unknown_column (unrecognised alias) → Mutation (no-op delta)" do
      expect(call("without unknown_column")).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "Mutation payload does NOT carry surface (reply elevation removed)" do
      expect(call("without channel").payload).not_to have_key("surface")
    end

    it "Mutation payload preserves reply_handle from source event" do
      expect(call("without views").payload["reply_handle"]).to eq("abc123")
    end

    it "Mutation payload preserves reply_target from source event" do
      expect(call("without views").payload["reply_target"]).to eq("video_list")
    end

    it "does NOT delegate to ToolDelegator" do
      call("without views")
      expect(Pito::FollowUp::ToolDelegator).not_to have_received(:call)
    end
  end

  # ── `sort` → Result::Mutation ─────────────────────────────────────────────────
  #
  # Every SORT_VOCAB token, every direction keyword, and the optional leading
  # 'by' particle.  sort_key_for is stubbed to nil so video doubles need no
  # attribute stubs — the no-op path still produces a Mutation.

  describe "sort <col> [asc|desc] → Result::Mutation (in-place re-sort)" do
    {
      # Base columns (requires_with: false — always valid)
      "sort id"               => "SORT_SPECS[:id] — base column, always sortable",
      "sort title"            => "SORT_SPECS[:title] — base column, always sortable",
      # SORT_VOCAB entries (requires_with: true, gated by selected_columns)
      "sort channel"          => "SORT_VOCAB: 'channel' → :channel",
      "sort handle"           => "SORT_VOCAB: 'handle' → :channel",
      "sort visibility"       => "SORT_VOCAB: 'visibility' → :visibility",
      "sort game"             => "SORT_VOCAB: 'game' → :game",
      "sort games"            => "SORT_VOCAB: 'games' → :game",
      "sort duration"         => "SORT_VOCAB: 'duration' → :duration",
      "sort views"            => "SORT_VOCAB: 'views' → :views",
      "sort likes"            => "SORT_VOCAB: 'likes' → :likes",
      "sort comms"            => "SORT_VOCAB: 'comms' → :comments",
      "sort comments"         => "SORT_VOCAB: 'comments' → :comments",
      # Leading 'by' particle stripped
      "sort by views"         => "leading 'by' particle stripped",
      "sort by id"            => "leading 'by' particle stripped (base column)",
      # Direction suffixes
      "sort views asc"        => "trailing 'asc' stripped, direction: asc",
      "sort views desc"       => "trailing 'desc' stripped, direction: desc",
      "sort views ascending"  => "trailing 'ascending' keyword",
      "sort views descending" => "trailing 'descending' keyword",
      # by + direction combined
      "sort by views desc"    => "'by' + 'desc' combined",
      "sort by title asc"     => "'by' + 'asc' combined",
      "sort by likes descending" => "'by' + 'descending' combined",
      # Unknown sort token → lenient no-op
      "sort xyz"              => "unknown sort token → lenient no-op, still Mutation"
    }.each do |rest, note|
      it "#{rest.inspect} (#{note}) → Mutation" do
        expect(call(rest)).to be_a(Pito::FollowUp::Result::Mutation)
      end
    end

    it "Mutation kind reflects source event kind" do
      expect(call("sort title").kind).to eq(:system)
    end

    it "Mutation payload does NOT carry surface (reply elevation removed)" do
      expect(call("sort views").payload).not_to have_key("surface")
    end

    it "Mutation payload preserves reply_handle" do
      expect(call("sort id").payload["reply_handle"]).to eq("abc123")
    end

    it "Mutation payload preserves reply_target" do
      expect(call("sort id").payload["reply_target"]).to eq("video_list")
    end

    it "does NOT delegate to ToolDelegator" do
      call("sort views")
      expect(Pito::FollowUp::ToolDelegator).not_to have_received(:call)
    end
  end

  # ── `order` (alias for sort) → Result::Mutation ───────────────────────────────

  describe "order <col> [asc|desc] → Result::Mutation (sort alias)" do
    {
      "order views"              => "basic",
      "order id"                 => "base column",
      "order title"              => "base column",
      "order channel"            => "SORT_VOCAB: channel",
      "order handle"             => "SORT_VOCAB: handle → channel",
      "order visibility"         => "SORT_VOCAB: visibility",
      "order game"               => "SORT_VOCAB: game",
      "order games"              => "SORT_VOCAB: games",
      "order duration"           => "SORT_VOCAB: duration",
      "order likes"              => "SORT_VOCAB: likes",
      "order comms"              => "SORT_VOCAB: comms",
      "order comments"           => "SORT_VOCAB: comments",
      "order by views"           => "with leading 'by'",
      "order by likes desc"      => "'by' + 'desc'",
      "order by title asc"       => "'by' + 'asc'",
      "order views ascending"    => "trailing 'ascending'",
      "order views descending"   => "trailing 'descending'",
      "order by views descending" => "'by' + 'descending'",
      "order xyz"                => "unknown token → lenient no-op, still Mutation"
    }.each do |rest, note|
      it "#{rest.inspect} (#{note}) → Mutation" do
        expect(call(rest)).to be_a(Pito::FollowUp::Result::Mutation)
      end
    end

    it "does NOT delegate to ToolDelegator" do
      call("order views")
      expect(Pito::FollowUp::ToolDelegator).not_to have_received(:call)
    end
  end

  # ── Delegated actions → ToolDelegator ────────────────────────────────────────
  #
  # All declared actions that are NOT with/without/sort/order go directly to
  # ToolDelegator.  ToolDelegator is stubbed to the sentinel — we test ROUTING
  # only (not the downstream chat handler execution or DB effects).

  describe "delegated actions → ToolDelegator (not invalid_action)" do
    {
      # show
      "show"     => "show 10",
      # delete aliases
      "delete"   => "delete 10",
      "del"      => "del 10",
      "rm"       => "rm 10",
      # scheduling
      "schedule" => "schedule 10 today at 14:00",
      # visibility
      "publish"  => "publish 10",
      "pub"      => "pub 10",
      "unlist"   => "unlist 10",
      # linking
      "link"     => "link 10 to 5",
      "unlink"   => "unlink 10 from 5",
      # shinies
      "shinies"  => "shinies 10"
    }.each do |action, rest_input|
      context "#{action.inspect} (rest: #{rest_input.inspect})" do
        subject(:result) { call(rest_input) }

        it "does NOT return a Result::Error (action is gated in by the declared list)" do
          expect(result).not_to be_a(Pito::FollowUp::Result::Error)
        end

        it "delegates to ToolDelegator.call with source_event + rest + conversation" do
          result
          expect(Pito::FollowUp::ToolDelegator).to have_received(:call).with(
            hash_including(source_event: source_event, rest: rest_input, conversation: conversation)
          )
        end

        it "returns the sentinel Append from ToolDelegator" do
          expect(result).to eq(sentinel)
        end
      end
    end
  end

  # ── Unknown action → Result::Error ───────────────────────────────────────────
  #
  # The handler's `else` branch calls ToolDelegator for EVERY non-mutate action.
  # ToolDelegator gates by the declared action list — unknown verbs short-circuit
  # with the invalid_action Error before reaching Chat::Dispatcher.
  # We let ToolDelegator run for real here (pure registry lookup, no DB).

  describe "unknown action → invalid_action Error" do
    before do
      # Override the global stub: let ToolDelegator's own gating fire for real.
      allow(Pito::FollowUp::ToolDelegator).to receive(:call).and_call_original
    end

    %w[channel sync visit studio foo bar baz].each do |action|
      context "#{action.inspect}" do
        subject(:result) { call("#{action} whatever") }

        it "returns a Result::Error" do
          expect(result).to be_a(Pito::FollowUp::Result::Error)
        end

        it "uses the video_list invalid_action message key" do
          expect(result.message_key).to eq("pito.follow_up.video_list.errors.invalid_action")
        end

        it "includes the unknown action in message_args" do
          expect(result.message_args).to include(action: action)
        end
      end
    end

    context "empty rest (blank verb)" do
      subject(:result) { call("") }

      it "returns a Result::Error (empty verb is not in the declared action list)" do
        expect(result).to be_a(Pito::FollowUp::Result::Error)
      end
    end
  end
end
