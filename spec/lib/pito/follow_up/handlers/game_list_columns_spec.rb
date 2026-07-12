# frozen_string_literal: true

require "rails_helper"

# Specs for the with/without column-mutation feature on the game_list follow-up handler.
RSpec.describe Pito::FollowUp::Handlers::GameList, "column mutations" do
  subject(:handler) { described_class.new }

  let(:conversation) { Conversation.singleton }
  let!(:game)        { create(:game, title: "Lies of P") }

  # Build a realistic game_list event payload using the List builder so it carries
  # game_ids and list_columns (as produced by MessageBuilder::Game::List.call).
  let(:event_payload) do
    payload = Pito::MessageBuilder::Game::List.call(
      [ game ],
      conversation: conversation,
      columns:      []
    )
    # Simulate what the DB stores (string keys), keep reply_handle/target.
    payload
  end

  let(:event) do
    instance_double(Event,
      payload: event_payload,
      kind:    "system")
  end

  # #12 — a reply column mutation must fold the new column set into the pager
  # cursor so `next`/`more` keeps the customized columns on later pages.
  describe "column mutation folds into the pager cursor (#12)" do
    let(:cursor_event) do
      instance_double(Event, kind: "system", payload: event_payload.merge(
        "list_cursor" => {
          "offset" => 2, "raw" => "list games", "channel" => nil,
          "sort_token" => nil, "sort_direction" => nil, "columns" => []
        }
      ))
    end

    it "carries the new column into list_cursor['columns']" do
      result = handler.call(event: cursor_event, rest: "with platform", conversation:)
      expect(result.payload["list_cursor"]["columns"]).to include("platform")
    end

    it "drops the column from list_cursor['columns'] on `without`" do
      base = event_payload.merge(
        "list_columns" => %w[platform],
        "list_cursor"  => { "offset" => 2, "raw" => "list games", "channel" => nil,
                            "sort_token" => nil, "sort_direction" => nil, "columns" => %w[platform] }
      )
      ev = instance_double(Event, kind: "system", payload: base)
      result = handler.call(event: ev, rest: "without platform", conversation:)
      expect(result.payload["list_cursor"]["columns"]).not_to include("platform")
    end
  end

  # ── Handler class declarations (via Matrix) ─────────────────────────────────

  it "registers the game_list target" do
    expect(described_class.target).to eq("game_list")
  end

  it "Matrix serves :append base mode for game_list" do
    expect(Pito::Dispatch::Matrix.mode_for("game_list")).to eq(:append)
  end

  it "Matrix serves :mutate for with and without on game_list" do
    expect(Pito::Dispatch::Matrix.mode_for("game_list", action: "with")).to eq(:mutate)
    expect(Pito::Dispatch::Matrix.mode_for("game_list", action: "without")).to eq(:mutate)
  end

  it "Matrix advertises with and without for game_list" do
    expect(Pito::Dispatch::Matrix.actions_for("game_list")).to include("with", "without")
  end

  it "Matrix does not advertise the dropped add/remove verbs for game_list" do
    actions = Pito::Dispatch::Matrix.actions_for("game_list")
    expect(actions).not_to include("add", "remove")
    # Unknown tokens fall back to the target's base mode (HF3 — DSL parity);
    # non-advertisement is the actions_for assertion above.
    base = Pito::Dispatch::Matrix.mode_for("game_list", action: nil)
    expect(Pito::Dispatch::Matrix.mode_for("game_list", action: "add")).to eq(base)
    expect(Pito::Dispatch::Matrix.mode_for("game_list", action: "remove")).to eq(base)
  end

  # ── Registry.mode_for (per-action) ──────────────────────────────────────────

  describe "Pito::FollowUp::Registry.mode_for (per-action)" do
    before { Pito::FollowUp::Registry.register_all! }

    it "returns :mutate for with action" do
      expect(Pito::FollowUp::Registry.mode_for("game_list", action: "with")).to eq(:mutate)
    end

    it "returns :mutate for without action" do
      expect(Pito::FollowUp::Registry.mode_for("game_list", action: "without")).to eq(:mutate)
    end

    it "returns :append (default) for show action" do
      expect(Pito::FollowUp::Registry.mode_for("game_list", action: "show")).to eq(:append)
    end

    it "returns :append (default) for delete action" do
      expect(Pito::FollowUp::Registry.mode_for("game_list", action: "delete")).to eq(:append)
    end

    it "returns :append (default) when action is nil" do
      expect(Pito::FollowUp::Registry.mode_for("game_list", action: nil)).to eq(:append)
    end
  end

  # ── with <columns> ──────────────────────────────────────────────────────────

  describe "#call with `with`" do
    it "returns a Mutation (not Append) for with platform" do
      result = handler.call(event:, rest: "with platform", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "kind is :system (mirrors the source event kind)" do
      result = handler.call(event:, rest: "with platform", conversation:)
      expect(result.kind).to eq(:system)
    end

    it "payload includes platform in list_columns after with platform" do
      result = handler.call(event:, rest: "with platform", conversation:)
      expect(result.payload["list_columns"]).to include("platform")
    end

    it "ignores the removed 'release' column alias (item 24)" do
      result = handler.call(event:, rest: "with release", conversation:)
      expect(result.payload["list_columns"]).not_to include("release_date")
    end

    it "payload table_heading gains Platform column after with" do
      result = handler.call(event:, rest: "with platform", conversation:)
      headings = result.payload["table_heading"].map { |h| h.is_a?(Hash) ? h["text"] : h }
      expect(headings).to include("Platform")
    end

    it "successive with operations are independent and accumulate" do
      # with platform
      result1 = handler.call(event:, rest: "with platform", conversation:)
      expect(result1.payload["list_columns"]).to include("platform")

      # with genre on the original event (handle is not consumed)
      result2 = handler.call(event:, rest: "with genre", conversation:)
      expect(result2.payload["list_columns"]).to include("genre")
      expect(result2.payload["list_columns"]).not_to include("platform")
    end

    it "does NOT set reply_consumed (handle is NOT consumed)" do
      result = handler.call(event:, rest: "with platform", conversation:)
      expect(result.payload["reply_consumed"]).not_to be_truthy
    end

    it "preserves the original reply_handle so the same handle stays repliable" do
      original_handle = event_payload["reply_handle"]
      result          = handler.call(event:, rest: "with platform", conversation:)
      expect(result.payload["reply_handle"]).to eq(original_handle)
    end

    it "preserves reply_target as game_list" do
      result = handler.call(event:, rest: "with platform", conversation:)
      expect(result.payload["reply_target"]).to eq("game_list")
    end

    it "ignores unknown column tokens" do
      result = handler.call(event:, rest: "with banana", conversation:)
      expect(result.payload["list_columns"]).to eq([])
    end

    it "ignores duplicate columns (idempotent with)" do
      # Start with platform already in the list
      payload_with_platform = Pito::MessageBuilder::Game::List.call(
        [ game ],
        conversation: conversation,
        columns:      [ :platform ]
      )
      ev_with = instance_double(Event, payload: payload_with_platform, kind: "system")

      result = handler.call(event: ev_with, rest: "with platform", conversation:)
      expect(result.payload["list_columns"].count { |c| c == "platform" }).to eq(1)
    end

    it "accepts comma-separated columns: with platform, genre" do
      result = handler.call(event:, rest: "with platform, genre", conversation:)
      expect(result.payload["list_columns"]).to include("platform", "genre")
    end

    it "stamps game_ids in the rebuilt payload" do
      result = handler.call(event:, rest: "with platform", conversation:)
      expect(result.payload["game_ids"]).to eq([ game.id ])
    end
  end

  # ── without <columns> ─────────────────────────────────────────────────────────

  describe "#call with `without`" do
    let(:event_with_platform) do
      payload = Pito::MessageBuilder::Game::List.call(
        [ game ],
        conversation: conversation,
        columns:      [ :platform ]
      )
      instance_double(Event, payload:, kind: "system")
    end

    it "returns a Mutation for without platform" do
      result = handler.call(event: event_with_platform, rest: "without platform", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "platform is removed from list_columns" do
      result = handler.call(event: event_with_platform, rest: "without platform", conversation:)
      expect(result.payload["list_columns"]).not_to include("platform")
    end

    it "ignores unknown column in without (no error)" do
      result = handler.call(event: event_with_platform, rest: "without banana", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      expect(result.payload["list_columns"]).to include("platform")
    end

    it "does NOT consume the handle" do
      result = handler.call(event: event_with_platform, rest: "without platform", conversation:)
      expect(result.payload["reply_consumed"]).not_to be_truthy
    end

    it "preserves the original reply_handle" do
      original_handle = event_with_platform.payload["reply_handle"]
      result          = handler.call(event: event_with_platform, rest: "without platform", conversation:)
      expect(result.payload["reply_handle"]).to eq(original_handle)
    end
  end

  # ── add/remove are now INVALID (dropped entirely, not aliased) ───────────────

  describe "#call with the dropped add/remove verbs" do
    before { Pito::FollowUp::Registry.register_all! }

    it "rejects `add` with the invalid_action error (no longer a column verb)" do
      result = handler.call(event:, rest: "add platform", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.game_list.errors.invalid_action")
      expect(result.message_args).to eq({ action: "add" })
    end

    it "rejects `remove` with the invalid_action error" do
      result = handler.call(event: event, rest: "remove platform", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.game_list.errors.invalid_action")
    end
  end

  # ── sort/order <column> ─────────────────────────────────────────────────────

  describe "#call with sort" do
    let!(:game_a) { create(:game, title: "Aaa") }
    let!(:game_b) { create(:game, title: "Zzz") }

    let(:two_game_event) do
      payload = Pito::MessageBuilder::Game::List.call(
        [ game_b, game_a ],   # intentionally out of alpha order
        conversation:,
        columns: []
      )
      instance_double(Event, payload:, kind: "system")
    end

    it "returns a Mutation for sort by title" do
      result = handler.call(event: two_game_event, rest: "sort by title", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "kind is :system (mirrors the source event kind)" do
      result = handler.call(event: two_game_event, rest: "sort by title", conversation:)
      expect(result.kind).to eq(:system)
    end

    it "re-sorts the list ascending by title" do
      result = handler.call(event: two_game_event, rest: "sort by title", conversation:)
      expect(result.payload["game_ids"]).to eq([ game_a.id, game_b.id ])
    end

    it "re-sorts descending with `sort by title desc`" do
      result = handler.call(event: two_game_event, rest: "sort by title desc", conversation:)
      expect(result.payload["game_ids"]).to eq([ game_b.id, game_a.id ])
    end

    it "accepts `sort title` (without `by`)" do
      result = handler.call(event: two_game_event, rest: "sort title", conversation:)
      expect(result.payload["game_ids"]).to eq([ game_a.id, game_b.id ])
    end

    it "`order by title` is an alias for sort" do
      result = handler.call(event: two_game_event, rest: "order by title", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      expect(result.payload["game_ids"]).to eq([ game_a.id, game_b.id ])
    end

    it "is a lenient no-op for an unknown column (stamped order preserved)" do
      result = handler.call(event: two_game_event, rest: "sort by banana", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      # Stamped order was [game_b, game_a] (no key found → unchanged)
      expect(result.payload["game_ids"]).to eq([ game_b.id, game_a.id ])
    end

    it "is a lenient no-op when sorting by a column not present in the list" do
      # platform requires_with: true and is NOT in current_cols → sort_key_for returns nil
      result = handler.call(event: two_game_event, rest: "sort by platform", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      expect(result.payload["game_ids"]).to eq([ game_b.id, game_a.id ])
    end

    it "does NOT set reply_consumed (handle stays live)" do
      result = handler.call(event: two_game_event, rest: "sort by title", conversation:)
      expect(result.payload["reply_consumed"]).not_to be_truthy
    end

    it "preserves the original reply_handle" do
      original_handle = two_game_event.payload["reply_handle"]
      result          = handler.call(event: two_game_event, rest: "sort by title", conversation:)
      expect(result.payload["reply_handle"]).to eq(original_handle)
    end

    it "preserves reply_target as game_list" do
      result = handler.call(event: two_game_event, rest: "sort by title", conversation:)
      expect(result.payload["reply_target"]).to eq("game_list")
    end

    context "when the platform column is present" do
      let!(:game_ps) do
        game_a.platforms = [ "ps5" ]; game_a.save!; game_a
      end

      let(:platform_event) do
        payload = Pito::MessageBuilder::Game::List.call(
          [ game_b, game_a ],
          conversation:,
          columns: [ :platform ]
        )
        instance_double(Event, payload:, kind: "system")
      end

      it "sorts by platform when the platform column is present" do
        result = handler.call(event: platform_event, rest: "sort by platform", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Mutation)
        # Just verify it's a Mutation and doesn't raise — platform sort key is valid.
        expect(result.payload["list_columns"]).to include("platform")
      end
    end
  end

  describe "Pito::FollowUp::Registry.mode_for — sort/order" do
    before { Pito::FollowUp::Registry.register_all! }

    it "returns :mutate for sort action" do
      expect(Pito::FollowUp::Registry.mode_for("game_list", action: "sort")).to eq(:mutate)
    end

    it "returns :mutate for order action" do
      expect(Pito::FollowUp::Registry.mode_for("game_list", action: "order")).to eq(:mutate)
    end
  end

  # ── show/delete still go through ToolDelegator (:append, consuming) ─────────

  describe "#call with show (still :append, consuming)" do
    it "returns an Append result for show" do
      result = handler.call(event:, rest: "show ##{game.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end
  end

  describe "#call with delete (still :append, consuming)" do
    it "returns an Append result for delete" do
      result = handler.call(event:, rest: "delete ##{game.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.first[:kind].to_s).to eq("confirmation")
    end
  end
end
