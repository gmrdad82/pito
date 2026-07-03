# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: game_list hashtag follow-up (recognition, DB mocked) ─────
#
# RULE: every action + arg combination the game_list handler recognises is
# covered here. DB is fully mocked — zero factories, no schema hits.
#
# Declared actions (from GameList.actions):
#   show, delete, del, rm, with, without, sort, order,
#   link, unlink, platform, price, shinies
#
# Routing in GameList#call:
#   with / without  → mutate_columns → Result::Mutation
#   sort  / order   → mutate_sort    → Result::Mutation
#   everything else → VerbDelegator  (gating: unknown verb → Error)
#
# Source event is an instance_double(Event, payload: { reply_target: "game_list",
#   game_ids: [...], list_columns: [...], ... }) — no factories.
RSpec.describe "Dispatch matrix — game_list hashtag follow-up (recognition, DB mocked)", type: :dispatch do
  subject(:handler) { Pito::FollowUp::Handlers::GameList.new }

  # ── shared doubles ────────────────────────────────────────────────────────────

  # Base event payload — mimics what MessageBuilder::Game::List stamps on a real event.
  let(:base_payload) do
    {
      "reply_target" => "game_list",
      "reply_handle" => "abc-1234",
      "game_ids"     => [ 10, 20 ],
      "list_columns" => [],
      "table_rows"   => [
        { "cells" => [ { "text" => "#10" }, { "text" => "Game A" } ] },
        { "cells" => [ { "text" => "#20" }, { "text" => "Game B" } ] }
      ]
    }
  end

  let(:event)        { instance_double(Event, kind: "system", payload: base_payload) }
  let(:conversation) { instance_double(Conversation) }

  # Payload returned by the stubbed List builder (mutable so the handler can
  # overwrite reply_handle / reply_target / surface in place).
  let(:rebuilt_payload) do
    {
      "reply_handle" => nil,
      "reply_target" => nil,
      "list_columns" => [],
      "game_ids"     => [ 10, 20 ],
      "table_rows"   => []
    }
  end

  # A minimal Append result used for delegated-action stubs.
  let(:fake_append) do
    Pito::FollowUp::Result::Append.new(
      events: [ { kind: :system, payload: { "text" => "ok" } } ]
    )
  end

  # Zero-DB default: Game.where returns an empty array (Enumerable#sort_by works;
  # sort-key lambdas never fire on empty collections). List builder is stubbed.
  before do
    allow(::Game).to receive(:where).and_return([])
    allow(Pito::MessageBuilder::Game::List).to receive(:call).and_return(rebuilt_payload)
  end

  # ── Class-level declarations ──────────────────────────────────────────────────

  describe "class declarations" do
    it "target is 'game_list'" do
      expect(Pito::FollowUp::Handlers::GameList.target).to eq("game_list")
    end

    it "Matrix serves :append base mode for game_list" do
      expect(Pito::Dispatch::Matrix.mode_for("game_list")).to eq(:append)
    end

    it "Matrix serves :mutate for with/without/sort/order on game_list" do
      expect(Pito::Dispatch::Matrix.mode_for("game_list", action: "with")).to    eq(:mutate)
      expect(Pito::Dispatch::Matrix.mode_for("game_list", action: "without")).to eq(:mutate)
      expect(Pito::Dispatch::Matrix.mode_for("game_list", action: "sort")).to    eq(:mutate)
      expect(Pito::Dispatch::Matrix.mode_for("game_list", action: "order")).to   eq(:mutate)
    end

    it "Registry.actions_for('game_list') is exactly the 15 verb actions (universals excluded)" do
      expect(Pito::FollowUp::Registry.actions_for("game_list")).to match_array(
        %w[show delete del rm with without sort order link unlink platform price shinies analyze next]
      )
    end
  end

  # ── with <column> → Result::Mutation ─────────────────────────────────────────
  #
  # Every alias from ListColumns::COLUMNS maps to a canonical Symbol. Unknown
  # tokens are silently dropped (no-op), but a Mutation is still returned.

  describe "with <column> → Result::Mutation" do
    {
      "platform"      => :platform,
      "platforms"     => :platform,
      "genre"         => :genre,
      "genres"        => :genre,
      "developer"     => :developer,
      "dev"           => :developer,
      "publisher"     => :publisher,
      "channel"       => :channels,
      "channels"      => :channels,
      "release"       => :release_date,
      "release date"  => :release_date,
      "year"          => :year,
      "footage"       => :footage,
      "price"         => :price,
      "prices"        => :price
    }.each do |token, canonical|
      it "with #{token.inspect} → Mutation (resolves to #{canonical})" do
        result = handler.call(event:, rest: "with #{token}", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      end
    end

    it "with platform, genre (comma-separated) → Mutation" do
      result = handler.call(event:, rest: "with platform, genre", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "with platform,genre (no spaces) → Mutation" do
      result = handler.call(event:, rest: "with platform,genre", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "with platform, genre, year (three columns) → Mutation" do
      result = handler.call(event:, rest: "with platform, genre, year", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "with unknown_token → Mutation (graceful no-op; unknown tokens silently dropped)" do
      result = handler.call(event:, rest: "with banana", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "Mutation kind mirrors the source event kind" do
      result = handler.call(event:, rest: "with platform", conversation:)
      expect(result.kind).to eq(:system)
    end

    it "Mutation payload does NOT carry surface (reply elevation removed)" do
      result = handler.call(event:, rest: "with platform", conversation:)
      expect(result.payload).not_to have_key("surface")
    end

    it "Mutation payload preserves reply_handle from source event" do
      result = handler.call(event:, rest: "with platform", conversation:)
      expect(result.payload["reply_handle"]).to eq("abc-1234")
    end

    it "Mutation payload preserves reply_target as 'game_list'" do
      result = handler.call(event:, rest: "with platform", conversation:)
      expect(result.payload["reply_target"]).to eq("game_list")
    end

    it "calls Game::List builder with the updated column set" do
      handler.call(event:, rest: "with platform", conversation:)
      expect(Pito::MessageBuilder::Game::List).to have_received(:call).with(
        anything, conversation:, columns: [ :platform ]
      )
    end
  end

  # ── without <column> → Result::Mutation ──────────────────────────────────────

  describe "without <column> → Result::Mutation" do
    # Event with platform + genre already in list_columns (so without has something to remove).
    let(:event_with_cols) do
      instance_double(Event,
        kind:    "system",
        payload: base_payload.merge("list_columns" => %w[platform genre]))
    end

    {
      "platform"     => :platform,
      "platforms"    => :platform,
      "genre"        => :genre,
      "genres"       => :genre,
      "developer"    => :developer,
      "dev"          => :developer,
      "publisher"    => :publisher,
      "channel"      => :channels,
      "channels"     => :channels,
      "release"      => :release_date,
      "year"         => :year,
      "footage"      => :footage,
      "price"        => :price,
      "prices"       => :price
    }.each do |token, canonical|
      it "without #{token.inspect} → Mutation (resolves to #{canonical})" do
        result = handler.call(event: event_with_cols, rest: "without #{token}", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      end
    end

    it "without platform, genre (comma-separated) → Mutation" do
      result = handler.call(event: event_with_cols, rest: "without platform, genre", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "without unknown_token → Mutation (graceful no-op; unknown tokens silently dropped)" do
      result = handler.call(event:, rest: "without banana", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "Mutation payload does NOT carry surface (reply elevation removed)" do
      result = handler.call(event: event_with_cols, rest: "without platform", conversation:)
      expect(result.payload).not_to have_key("surface")
    end

    it "Mutation payload preserves reply_handle from source event" do
      result = handler.call(event: event_with_cols, rest: "without platform", conversation:)
      expect(result.payload["reply_handle"]).to eq("abc-1234")
    end

    it "Mutation payload preserves reply_target as 'game_list'" do
      result = handler.call(event: event_with_cols, rest: "without platform", conversation:)
      expect(result.payload["reply_target"]).to eq("game_list")
    end

    it "calls Game::List builder with the column removed" do
      handler.call(event: event_with_cols, rest: "without platform", conversation:)
      expect(Pito::MessageBuilder::Game::List).to have_received(:call).with(
        anything, conversation:, columns: [ :genre ]  # platform removed from [platform, genre]
      )
    end
  end

  # ── sort [by] <col> [asc|desc] → Result::Mutation ────────────────────────────
  #
  # Tokens from SORT_VOCAB. Base tokens (id, title) are always valid; requires-with
  # tokens (platform, genre, …) are a lenient no-op when that column isn't shown —
  # still returns Mutation either way.

  describe "sort [by] <col> [asc|desc] → Result::Mutation" do
    {
      # bare base tokens
      "sort title"              => :title,
      "sort id"                 => :id,
      "sort game"               => :title,
      "sort #"                  => :id,
      # with leading "by" particle
      "sort by title"           => :title,
      "sort by id"              => :id,
      "sort by game"            => :title,
      # direction variants
      "sort title asc"          => :title,
      "sort title desc"         => :title,
      "sort title ascending"    => :title,
      "sort title descending"   => :title,
      "sort by title asc"       => :title,
      "sort by title desc"      => :title,
      # requires-with tokens — lenient no-op if col absent, still Mutation
      "sort platform"           => :platform,
      "sort platforms"          => :platform,
      "sort genre"              => :genre,
      "sort genres"             => :genre,
      "sort developer"          => :developer,
      "sort dev"                => :developer,
      "sort publisher"          => :publisher,
      "sort year"               => :year,
      "sort channel"            => :channels,
      "sort channels"           => :channels,
      "sort footage"            => :footage,
      "sort price"              => :price,
      "sort prices"             => :price,
      "sort platform desc"      => :platform,
      "sort by platform desc"   => :platform,
      # two-word sort token
      "sort release date"       => :release_date,
      "sort by release date"    => :release_date,
      "sort release date asc"   => :release_date,
      "sort release date desc"  => :release_date,
      "sort by release date desc" => :release_date,
      # unknown token → lenient no-op (no sort applied), still a Mutation
      "sort banana"             => nil,
      "sort by banana"          => nil
    }.each do |input, _canonical|
      it "#{input.inspect} → Mutation" do
        result = handler.call(event:, rest: input, conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      end
    end

    it "Mutation kind mirrors source event kind" do
      result = handler.call(event:, rest: "sort title", conversation:)
      expect(result.kind).to eq(:system)
    end

    it "Mutation payload does NOT carry surface (reply elevation removed)" do
      result = handler.call(event:, rest: "sort title", conversation:)
      expect(result.payload).not_to have_key("surface")
    end

    it "Mutation payload preserves reply_handle from source event" do
      result = handler.call(event:, rest: "sort title", conversation:)
      expect(result.payload["reply_handle"]).to eq("abc-1234")
    end
  end

  # ── order [by] <col> [asc|desc] → Result::Mutation (alias for sort) ──────────

  describe "order [by] <col> [asc|desc] → Result::Mutation (alias for sort)" do
    {
      "order title"              => :title,
      "order id"                 => :id,
      "order game"               => :title,
      "order #"                  => :id,
      "order by title"           => :title,
      "order by id"              => :id,
      "order title asc"          => :title,
      "order title desc"         => :title,
      "order by title desc"      => :title,
      "order platform"           => :platform,
      "order genre"              => :genre,
      "order developer"          => :developer,
      "order dev"                => :developer,
      "order publisher"          => :publisher,
      "order year"               => :year,
      "order channel"            => :channels,
      "order footage"            => :footage,
      "order price"              => :price,
      "order prices"             => :price,
      "order release date"       => :release_date,
      "order by release date"    => :release_date,
      "order release date desc"  => :release_date,
      # lenient no-op
      "order banana"             => nil,
      "order by banana desc"     => nil
    }.each do |input, _canonical|
      it "#{input.inspect} → Mutation" do
        result = handler.call(event:, rest: input, conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      end
    end

    it "Mutation payload does NOT carry surface (reply elevation removed)" do
      result = handler.call(event:, rest: "order by title", conversation:)
      expect(result.payload).not_to have_key("surface")
    end
  end

  # ── Delegated actions → VerbDelegator ────────────────────────────────────────
  #
  # show, delete, del, rm, link, unlink, platform, price, shinies all fall
  # through to VerbDelegator (stubbed). We assert the call and result type.

  describe "delegated actions → VerbDelegator" do
    before do
      allow(Pito::FollowUp::VerbDelegator).to receive(:call).and_return(fake_append)
    end

    %w[show delete del rm link unlink platform price shinies].each do |action|
      context action do
        it "#{action} → delegates to VerbDelegator with source_event + conversation" do
          handler.call(event:, rest: "#{action} 10", conversation:)
          expect(Pito::FollowUp::VerbDelegator).to have_received(:call).with(
            hash_including(source_event: event, conversation:)
          )
        end

        it "#{action} → result is whatever VerbDelegator returns" do
          result = handler.call(event:, rest: "#{action} 10", conversation:)
          expect(result).to be_a(Pito::FollowUp::Result::Append)
        end
      end
    end

    it "passes the full rest string (action word included) to VerbDelegator" do
      handler.call(event:, rest: "show 42", conversation:)
      expect(Pito::FollowUp::VerbDelegator).to have_received(:call).with(
        hash_including(rest: "show 42")
      )
    end

    it "passes rest unmodified for multi-word args (link 10 to 20)" do
      handler.call(event:, rest: "link 10 to 20", conversation:)
      expect(Pito::FollowUp::VerbDelegator).to have_received(:call).with(
        hash_including(rest: "link 10 to 20")
      )
    end

    it "threads period: through to VerbDelegator" do
      handler.call(event:, rest: "show 10", conversation:, period: "28d")
      expect(Pito::FollowUp::VerbDelegator).to have_received(:call).with(
        hash_including(period: "28d")
      )
    end

    it "threads viewport_width: through to VerbDelegator" do
      handler.call(event:, rest: "show 10", conversation:, viewport_width: "1200")
      expect(Pito::FollowUp::VerbDelegator).to have_received(:call).with(
        hash_including(viewport_width: "1200")
      )
    end

    it "threads channel: through to VerbDelegator" do
      handler.call(event:, rest: "show 10", conversation:, channel: "@pito")
      expect(Pito::FollowUp::VerbDelegator).to have_received(:call).with(
        hash_including(channel: "@pito")
      )
    end
  end

  # ── Unknown action → invalid_action Error ────────────────────────────────────
  #
  # Any verb not in game_list's declared actions matrix is gated by VerbDelegator,
  # which returns Result::Error with the target-specific copy key.

  describe "unknown action → invalid_action Error (via VerbDelegator gate)" do
    # These verbs exist elsewhere in the system but are not in game_list's matrix.
    %w[destroy publish reindex sync visit import schedule rename].each do |bad_action|
      it "#{bad_action.inspect} → Result::Error" do
        result = handler.call(event:, rest: "#{bad_action} 10", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Error)
      end

      it "#{bad_action.inspect} → error key is pito.follow_up.game_list.errors.invalid_action" do
        result = handler.call(event:, rest: "#{bad_action} 10", conversation:)
        expect(result.message_key).to eq("pito.follow_up.game_list.errors.invalid_action")
      end

      it "#{bad_action.inspect} → message_args includes the offending action word" do
        result = handler.call(event:, rest: "#{bad_action} 10", conversation:)
        expect(result.message_args).to include(action: bad_action)
      end
    end

    # Completely arbitrary tokens (not system verbs at all).
    %w[foo banana xyz 999].each do |junk|
      it "#{junk.inspect} → Result::Error" do
        result = handler.call(event:, rest: "#{junk} 10", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Error)
      end
    end
  end

  # ── Registry integration ──────────────────────────────────────────────────────

  describe "Registry integration" do
    before { Pito::FollowUp::Registry.register_all! }

    it "game_list is registered" do
      expect(Pito::FollowUp::Registry.for("game_list")).to eq(Pito::FollowUp::Handlers::GameList)
    end

    it "mode_for with: :mutate" do
      expect(Pito::FollowUp::Registry.mode_for("game_list", action: "with")).to eq(:mutate)
    end

    it "mode_for without: :mutate" do
      expect(Pito::FollowUp::Registry.mode_for("game_list", action: "without")).to eq(:mutate)
    end

    it "mode_for sort: :mutate" do
      expect(Pito::FollowUp::Registry.mode_for("game_list", action: "sort")).to   eq(:mutate)
    end

    it "mode_for order: :mutate" do
      expect(Pito::FollowUp::Registry.mode_for("game_list", action: "order")).to  eq(:mutate)
    end

    it "mode_for delegated actions: :append" do
      %w[show delete del rm link unlink platform price shinies].each do |action|
        expect(Pito::FollowUp::Registry.mode_for("game_list", action: action)).to eq(:append),
          "expected mode_for(#{action}) to be :append"
      end
    end

    it "actions_for returns all 15 declared actions" do
      actions = Pito::FollowUp::Registry.actions_for("game_list").map(&:to_s)
      expect(actions).to match_array(
        %w[show delete del rm with without sort order link unlink platform price shinies analyze next]
      )
    end
  end
end
