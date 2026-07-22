# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::ChannelList do
  subject(:handler) { described_class.new }

  let(:conversation) { Conversation.singleton }
  let!(:channel) do
    create(:channel,
           title:              "Alpha Cast",
           handle:             "@alpha",
           youtube_channel_id: "UCabc")
  end

  it "registers for the channel_list target" do
    expect(described_class.target).to eq("channel_list")
  end

  it "Matrix serves :append mode for channel_list" do
    expect(Pito::Dispatch::Matrix.mode_for("channel_list")).to eq(:append)
  end

  it "Matrix advertises shinies, visit, analyze, sort/order, and next for channel_list (T9: visit config-declared)" do
    actions = Pito::Dispatch::Matrix.actions_for("channel_list")
    expect(actions).to include("shinies", "visit", "analyze", "sort", "order", "next")
  end

  describe "`@ai <text>` — anchored reply (owner-scoped roster)" do
    let(:ai_event) do
      instance_double(Event, id: 4244, payload: {
        "reply_target" => "channel_list",
        "channel_ids"  => [ channel.id ]
      })
    end

    it "delegates to Chat::Handlers::Ai via ToolDelegator: a pending :ai event anchored on this list" do
      result = handler.call(event: ai_event, rest: "@ai who's my biggest channel", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to be(false)
      pending = result.events.first
      expect(pending[:kind]).to eq(:ai)
      expect(pending[:payload]["status"]).to eq("pending")
      expect(pending[:payload]["prompt"]).to eq("who's my biggest channel")
      expect(pending[:payload]["anchor_event_id"]).to eq(4244)
    end
  end

  describe "sort / order replies (mutate — table re-sorts in place)" do
    let(:conversation) { Conversation.singleton }
    let!(:turn)        { create(:turn, conversation:) }
    let!(:small) { create(:channel, title: "Small", handle: "@small", youtube_channel_id: "UCsml") }
    let!(:big)   { create(:channel, title: "Big",   handle: "@big",   youtube_channel_id: "UCbig") }

    let!(:event) do
      create(:event, conversation:, turn:, kind: "system", position: 1,
                     payload: Pito::MessageBuilder::Channel::List.call([ small, big ], conversation:))
    end

    before do
      allow(small).to receive(:subscriber_count).and_return(5)
      allow(big).to receive(:subscriber_count).and_return(500)
      allow(::Channel).to receive(:where).and_call_original
    end

    def handles_of(result)
      result.payload["table_rows"].map { |r| r[:cells][1][:text] }
    end

    it "re-sorts the stamped table by a column (sort by title)" do
      result = handler.call(event:, rest: "sort by title", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      expect(handles_of(result)).to eq([ "@big", "@small" ]) # Big < Small
    end

    it "honors a trailing desc (order title desc)" do
      result = handler.call(event:, rest: "order title desc", conversation:)
      expect(handles_of(result)).to eq([ "@small", "@big" ])
    end

    it "preserves the reply handle/target across the mutation" do
      result = handler.call(event:, rest: "sort by title", conversation:)
      expect(result.payload["reply_handle"]).to eq(event.payload["reply_handle"])
      expect(result.payload["reply_target"]).to eq("channel_list")
    end

    it "is a lenient no-op on an unknown column (stamped order kept)" do
      result = handler.call(event:, rest: "sort by price", conversation:)
      expect(handles_of(result)).to eq([ "@small", "@big" ])
    end

    # G82 regression (owner 2026-07-05: "replying with sort doesn't do
    # anything"): counters sort only while VISIBLE, so the handler must pass
    # the STAMPED selection to sort_key_for — without it every subs/views/vids
    # sort resolved nil and silently no-opped.
    it "sorts by a DEFAULT counter column (sort by subs) using the stamped selection" do
      Pito::Stats.set(small, :views, 5)
      Pito::Stats.set(big,   :views, 500)

      result = handler.call(event:, rest: "sort by views desc", conversation:)
      expect(handles_of(result)).to eq([ "@big", "@small" ])
    end

    it "keeps the stamped column selection across a sort (list_columns survives)" do
      result = handler.call(event:, rest: "sort by title", conversation:)
      expect(result.payload["list_columns"]).to eq(event.payload["list_columns"])
    end
  end

  it "visit IS in Registry.actions_for('channel_list') (T9: config-declared, ref: channel_by_handle)" do
    expect(Pito::FollowUp::Registry.actions_for("channel_list")).to include("visit")
  end

  # ── `next` pagination ────────────────────────────────────────────────────────
  # Stub page_size to 2; the default :channel factory includes a youtube_connection
  # so channels_relation (WHERE youtube_connection_id IS NOT NULL) picks them up.

  describe "`next` pagination" do
    let(:pager_stub) { { page_size: 2, more_tool: "next" } }
    let!(:c2) { create(:channel, handle: "@beta") }
    let!(:c3) { create(:channel, handle: "@gamma") }

    before do
      allow(Pito::Dispatch::Config).to receive(:pager)
        .with(tool: :list)
        .and_return(pager_stub)
    end

    # Cursor stamped after showing 2 of 3 channels (offset=2).
    let(:cursor_event) do
      instance_double(Event, payload: {
        "reply_target" => "channel_list",
        "list_cursor"  => {
          "offset"         => 2,
          "sort_token"     => nil,
          "sort_direction" => nil
        }
      })
    end

    # G125.4 (TUI contract catch): the stamped selection must survive `next` —
    # counter sorts are visibility-gated past page 1 and `with`-added columns
    # must not reset when paging.
    it "threads the stamped list_columns into the next batch" do
      ev = instance_double(Event, payload: {
        "reply_target" => "channel_list",
        "list_columns" => [ "views", "subs" ],
        "list_cursor"  => { "offset" => 2, "sort_token" => nil, "sort_direction" => nil }
      })
      result = handler.call(event: ev, rest: "next", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.first[:payload]["list_columns"]).to match_array(%w[views subs])
    end

    it "resolves a counter sort on the next batch via the stamped selection" do
      ev = instance_double(Event, payload: {
        "reply_target" => "channel_list",
        "list_columns" => [ "views" ],
        "list_cursor"  => { "offset" => 2, "sort_token" => "views", "sort_direction" => "desc" }
      })
      expect(Pito::MessageBuilder::Channel::ListColumns).to receive(:sort_key_for)
        .with("views", selected_columns: [ :views ]).and_call_original
      handler.call(event: ev, rest: "next", conversation:)
    end

    it "renders the final batch (1 channel) with no list_cursor" do
      result = handler.call(event: cursor_event, rest: "next", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.first[:payload]["list_cursor"]).to be_nil
    end

    context "mid-batch: 5 channels, page_size=2, offset=2" do
      let!(:c4) { create(:channel, handle: "@delta") }
      let!(:c5) { create(:channel, handle: "@epsilon") }

      let(:mid_cursor_event) do
        instance_double(Event, payload: {
          "reply_target" => "channel_list",
          "list_cursor"  => {
            "offset"         => 2,
            "sort_token"     => nil,
            "sort_direction" => nil
          }
        })
      end

      it "list_footer for mid-batch `next` contains count (2) and total (5)" do
        result = handler.call(event: mid_cursor_event, rest: "next", conversation:)
        footer = result.events.first[:payload]["list_footer"].to_s
        expect(footer).to include("2")
        expect(footer).to include("5")
      end

      it "rest = total − (offset + count) = 1 is reflected in footer" do
        # Force variant 1 which uses %{rest}: "%{count} here, %{rest} more in the system. `%{tool}`."
        Pito::Copy.sampler = ->(entries) { entries[1] }
        result = handler.call(event: mid_cursor_event, rest: "next", conversation:)
        footer = result.events.first[:payload]["list_footer"].to_s
        expect(footer).to include("1 more in the system")
      end
    end

    context "no cursor (completed list)" do
      let(:no_cursor_event) do
        instance_double(Event, payload: { "reply_target" => "channel_list" })
      end

      it "renders list_end copy" do
        result = handler.call(event: no_cursor_event, rest: "next", conversation:)
        text = result.events.first[:payload]["text"].to_s
        expect(text).to be_present
        expect(text).not_to match(/%\{/)
      end
    end
  end

  describe "invalid action" do
    it "returns Result::Error for an unknown action" do
      # A real event is required now: an unrecognized action routes through
      # ToolDelegator (mirrors GameList/VideoList), whose own Matrix-backed
      # gate rejects it — it reads source_event.payload before that gate.
      source_event = instance_double(Event, payload: { "reply_target" => "channel_list" })
      result = handler.call(event: source_event, rest: "open @alpha", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.channel_list.errors.invalid_action")
    end

    # T9: 'visit' is now a config-declared action for channel_list (ref:
    # channel_by_handle, args: destination) — it delegates to Chat::Handlers::
    # Visit via ToolDelegator instead of hitting THIS target's invalid_action
    # gate. A destination-less reply still errors, but from Chat::Handlers::
    # Visit's own not_found copy (ReplyBinding empties kwargs — including the
    # already-resolved ref — on the failed destination slot; see
    # spec/dispatch/reply_binding_spec.rb), not channel_list's invalid_action.
    it "'visit @alpha' with no destination returns Chat::Handlers::Visit's not_found error (not channel_list's invalid_action)" do
      source_event = instance_double(Event, payload: { "reply_target" => "channel_list" })
      result = handler.call(event: source_event, rest: "visit @alpha", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.chat.visit.errors.not_found")
    end
  end

  # ── visit (T9: delegated to Chat::Handlers::Visit via ToolDelegator) ─────────

  describe "#call — visit @handle <destination>" do
    let(:source_event) do
      instance_double(Event, payload: { "reply_target" => "channel_list" })
    end

    it "returns a Result::Append with the visit message for @handle" do
      result = handler.call(event: source_event, rest: "visit @alpha youtube", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      payload = result.events.first[:payload]
      expect(payload["body"]).to include("www.youtube.com/@alpha")
      expect(payload["channel_id"]).to eq(channel.id)
    end

    it "does NOT return an invalid_action error (visit is now a declared action)" do
      result = handler.call(event: source_event, rest: "visit @alpha youtube", conversation:)
      expect(result).not_to be_a(Pito::FollowUp::Result::Error)
    end

    it "resolves 'studio' to the Studio destination" do
      result = handler.call(event: source_event, rest: "visit @alpha studio", conversation:)
      payload = result.events.first[:payload]
      expect(payload["body"]).to include("studio.youtube.com/channel/UCabc")
    end
  end

  # ── shinies (delegated to Chat::Handlers::Shinies via ToolDelegator) ───────────

  describe "#call — shinies" do
    let(:source_event) do
      instance_double(Event, payload: { "reply_target" => "channel_list" })
    end

    it "returns a Result::Append with the shinies message for @handle" do
      result = handler.call(event: source_event, rest: "shinies @alpha", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      payload = result.events.first[:payload]
      expect(payload["body"]).to include("pito-achievement-shinies")
      expect(payload["channel_id"]).to eq(channel.id)
    end

    it "does NOT return an invalid_action error (shinies is now a declared action)" do
      result = handler.call(event: source_event, rest: "shinies @alpha", conversation:)
      expect(result).not_to be_a(Pito::FollowUp::Result::Error)
    end
  end
end
