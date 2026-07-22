# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::ChannelDetail, type: :service do
  subject(:handler) { described_class.new }

  let(:conversation) { Conversation.singleton }
  let!(:channel) do
    create(:channel,
           title:              "Alpha Cast",
           handle:             "@alpha",
           youtube_channel_id: "UCabc")
  end
  let(:turn) do
    conversation.turns.create!(
      input_kind: :hashtag, input_text: "#detail-1234 visit channel", position: 1
    )
  end

  def build_detail_event(payload_overrides = {})
    base_payload = {
      "body"         => "<div>channel card html</div>",
      "html"         => true,
      "channel_id"   => channel.id,
      "reply_handle" => "detail-1234",
      "reply_target" => "channel_detail"
    }.merge(payload_overrides)
    Event.create_with_position!(
      conversation:, turn:, kind: :system, payload: base_payload
    )
  end

  it "registers for the channel_detail target" do
    expect(described_class.target).to eq("channel_detail")
  end

  it "Matrix serves :append mode for channel_detail" do
    expect(Pito::Dispatch::Matrix.mode_for("channel_detail")).to eq(:append)
  end

  it "Matrix advertises visit, sync and analyze for channel_detail" do
    expect(Pito::Dispatch::Matrix.actions_for("channel_detail")).to include("visit", "sync", "analyze")
  end

  it "is NOT internal (appears in help and suggestions)" do
    expect(described_class.internal?).to be false
  end

  describe "`@ai <text>` — anchored reply (owner-scoped roster)" do
    let(:source_event) { build_detail_event }

    it "delegates to Chat::Handlers::Ai via ToolDelegator: a pending :ai event anchored on this card" do
      result = handler.call(event: source_event, rest: "@ai is this channel growing", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to be(false)
      pending = result.events.first
      expect(pending[:kind]).to eq(:ai)
      expect(pending[:payload]["status"]).to eq("pending")
      expect(pending[:payload]["prompt"]).to eq("is this channel growing")
      expect(pending[:payload]["anchor_event_id"]).to eq(source_event.id)
    end
  end

  # ── visit — delegated to ToolDelegator → Chat::Handlers::Visit (T9) ───────────
  #
  # The old DESTINATION_MAP special case is gone: `visit` is now config-declared
  # (tools.yml visit.reply.targets.channel_detail — ref: source_entity, args:
  # destination) and reaches Pito::Chat::Handlers::Visit through the SAME
  # ToolDelegator → Router path every other reply tool on this card takes.
  # These specs run the REAL pipeline end-to-end (nothing stubbed) to prove the
  # observable payload is unchanged: Chat::Handlers::Visit maps a resolved
  # "youtube" destination back to the LEGACY :channel symbol for a channel
  # subject (see that handler's class header), so "visit channel" / "visit
  # youtube" / "visit yt" all still stamp visit_destination "channel".

  describe "#call — visit channel (canonical destination)" do
    let(:source_event) { build_detail_event }

    subject(:result) { handler.call(event: source_event, rest: "visit channel", conversation:) }

    it "returns a Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "appends one system event" do
      expect(result.events.length).to eq(1)
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "renders the visiting shimmer" do
      expect(result.events.first[:payload]["body"]).to include("pito-network-shimmer")
    end

    it "includes the channel's YouTube URL (not Studio)" do
      expect(result.events.first[:payload]["body"]).to include("www.youtube.com/@alpha")
      expect(result.events.first[:payload]["body"]).not_to include("studio.youtube.com")
    end

    it "stamps visit_destination as 'channel'" do
      expect(result.events.first[:payload]["visit_destination"]).to eq("channel")
    end

    it "includes the auto-visit Stimulus controller" do
      expect(result.events.first[:payload]["body"]).to include('data-controller="pito--auto-visit"')
    end
  end

  # ── visit youtube / yt (synonyms) ─────────────────────────────────────────────

  describe "#call — visit youtube (synonym for channel)" do
    let(:source_event) { build_detail_event }

    it "resolves to the YouTube channel URL" do
      result = handler.call(event: source_event, rest: "visit youtube", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.first[:payload]["body"]).to include("www.youtube.com/@alpha")
      expect(result.events.first[:payload]["visit_destination"]).to eq("channel")
    end
  end

  describe "#call — visit yt (synonym for channel)" do
    let(:source_event) { build_detail_event }

    it "resolves to the YouTube channel URL" do
      result = handler.call(event: source_event, rest: "visit yt", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.first[:payload]["body"]).to include("www.youtube.com/@alpha")
      expect(result.events.first[:payload]["visit_destination"]).to eq("channel")
    end
  end

  # ── visit studio ─────────────────────────────────────────────────────────────

  describe "#call — visit studio" do
    let(:source_event) { build_detail_event }

    subject(:result) { handler.call(event: source_event, rest: "visit studio", conversation:) }

    it "returns a Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "includes the Studio URL (studio.youtube.com)" do
      expect(result.events.first[:payload]["body"]).to include("studio.youtube.com/channel/UCabc")
    end

    it "does NOT include the regular YouTube channel URL" do
      expect(result.events.first[:payload]["body"]).not_to include("www.youtube.com/@alpha")
    end

    it "stamps visit_destination as 'studio'" do
      expect(result.events.first[:payload]["visit_destination"]).to eq("studio")
    end
  end

  # ── bare visit / unknown destination word → not_found (T9 architecture note) ──
  #
  # ToolDelegator threads ReplyBinding's output uncritically (Pito::Dispatch::
  # ReplyBinding's documented Invalid-propagation: ANY failed slot empties the
  # WHOLE kwargs Hash, ref included — spec/dispatch/reply_binding_spec.rb pins
  # this). So once a destination word fails to resolve, kwargs[:ref] is ALSO
  # gone by the time Chat::Handlers::Visit runs, and its follow_up_visit sees a
  # nil ref before it ever reaches destination resolution — "Couldn't find
  # that" (pito.chat.visit.errors.not_found), not the old
  # channel_detail-specific needs_destination copy. The control flow (an Error
  # is returned, no visit card renders) is unchanged; only the copy/key is.

  describe "#call — bare visit (missing destination)" do
    let(:source_event) { build_detail_event }

    subject(:result) { handler.call(event: source_event, rest: "visit", conversation:) }

    it "returns a Result::Error" do
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end

    it "uses Chat::Handlers::Visit's not_found error key (ReplyBinding emptied kwargs on the failed destination slot)" do
      expect(result.message_key).to eq("pito.chat.visit.errors.not_found")
    end
  end

  # ── unknown destination word ─────────────────────────────────────────────────

  describe "#call — visit with unknown destination" do
    let(:source_event) { build_detail_event }

    it "returns a not_found error for an unrecognised word (see the architecture note above)" do
      result = handler.call(event: source_event, rest: "visit tiktok", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.chat.visit.errors.not_found")
    end
  end

  # ── unknown action ─────────────────────────────────────────────────────────

  describe "#call — unknown action" do
    let(:source_event) { build_detail_event }

    it "returns a Result::Error with invalid_action key" do
      result = handler.call(event: source_event, rest: "open", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.channel_detail.errors.invalid_action")
      expect(result.message_args[:action]).to eq("open")
    end
  end

  # ── regression guard: config↔handler contract ────────────────────────────────
  # games / vids / shinies / at-a-glance were declared in tools.yml for
  # channel_detail but shadowed by the `unless action == "visit"` reject. Every
  # config-declared reply verb (bar the follow-up-only specials) must reach the
  # matrix-gated ToolDelegator. `visit` (T9) is no longer a special — it is fully
  # delegated like every other declared reply tool, so it is no longer excluded
  # from this table (ToolDelegator is stubbed here, so its own destination
  # resolution never runs — this only proves the ROUTING, per the describe
  # blocks above for the real end-to-end behavior).
  describe "every config-declared reply verb reaches ToolDelegator" do
    let(:source_event) { build_detail_event }
    let(:sentinel)     { Pito::FollowUp::Result::Append.new(events: []) }
    before { allow(Pito::FollowUp::ToolDelegator).to receive(:call).and_return(sentinel) }

    specials  = %w[analyze] # follow-up-only, handled in-card
    delegated = Pito::FollowUp::Registry.actions_for("channel_detail") - specials

    delegated.each do |verb|
      it "delegates '#{verb}' instead of rejecting it" do
        expect(handler.call(event: source_event, rest: verb, conversation:)).to eq(sentinel)
      end
    end
  end

  # ── channel not found ───────────────────────────────────────────────────────

  describe "#call — channel missing from DB" do
    it "returns Chat::Handlers::Visit's not_found error (T9: source_entity Invalid empties kwargs — see the architecture note above)" do
      event = build_detail_event("channel_id" => 0)
      result = handler.call(event: event, rest: "visit channel", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.chat.visit.errors.not_found")
    end
  end

  # ── registry ─────────────────────────────────────────────────────────────────

  describe "registry" do
    it "is registered under 'channel_detail'" do
      expect(Pito::FollowUp::Registry.for("channel_detail")).to eq(described_class)
    end

    it "has mode :append" do
      expect(Pito::FollowUp::Registry.mode_for("channel_detail")).to eq(:append)
    end

    it "reports 'visit' as an available action via Registry" do
      expect(Pito::FollowUp::Registry.actions_for("channel_detail")).to include("visit")
    end
  end
end
