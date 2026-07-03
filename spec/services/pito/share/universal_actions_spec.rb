# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Share::UniversalActions do
  let(:conversation) { Conversation.create! }
  let(:turn) do
    conversation.turns.create!(
      position: Turn.next_position_for(conversation),
      input_kind: :chat,
      input_text: "hi"
    )
  end
  let(:event) do
    Event.create_with_position!(
      conversation:, turn:, kind: :system,
      payload: { "text" => "hello", "reply_handle" => "test-handle" }
    )
  end
  let(:handler) { described_class.new }

  describe "VERBS constants" do
    it "HELP_VERBS contains only help" do
      expect(described_class::HELP_VERBS).to eq(%w[help])
    end

    it "ALWAYS_AVAILABLE contains only share" do
      expect(described_class::ALWAYS_AVAILABLE).to eq(%w[share])
    end

    it "SHARE_REQUIRED contains revoke and unshare" do
      expect(described_class::SHARE_REQUIRED).to match_array(%w[revoke unshare])
    end

    it ".verbs derives from Matrix.universal_tokens (share, revoke, unshare, help)" do
      expect(described_class.verbs).to match_array(%w[help share revoke unshare])
    end
  end

  # Owner ruling 2026-07-03 (widened same day, D14): share applies to :system, :enhanced
  # AND their follow-up kinds (kinds: [system, enhanced, system_follow_up, enhanced_follow_up]
  # in universal_reply config). These tests pin that policy literally — one example per
  # excluded kind (thinking/echo/error/confirmation) and one per included kind.
  describe ".verbs_for — kind gating (owner ruling 2026-07-03)" do
    def event_of_kind(k)
      Event.create_with_position!(
        conversation:, turn:, kind: k,
        payload: { "text" => "x", "reply_handle" => "h-#{k}" }
      )
    end

    it "offers `help` and `share` for a non-shared :system message" do
      expect(described_class.verbs_for(event)).to match_array(%w[help share])
    end

    it "offers `help` and `share` for a non-shared :system_follow_up message (owner D14: follow-ups shareable)" do
      ev = event_of_kind("system_follow_up")
      expect(described_class.verbs_for(ev)).to include("help", "share")
    end

    it "offers `help` and `share` for a non-shared :enhanced_follow_up message (owner D14)" do
      ev = event_of_kind("enhanced_follow_up")
      expect(described_class.verbs_for(ev)).to include("help", "share")
    end

    it "offers `help` and `share` for a non-shared :enhanced message" do
      ev = event_of_kind(:enhanced)
      expect(described_class.verbs_for(ev)).to match_array(%w[help share])
    end

    it "adds revoke/unshare once the event has a Share" do
      Share.find_or_create_by!(event:) { |s| s.conversation = conversation }
      expect(described_class.verbs_for(event)).to match_array(%w[help share revoke unshare])
    end

    # Excluded kinds — owner ruling: NO share/revoke/unshare on any of these.
    it "offers ONLY `help` for a :confirmation message (owner 2026-06-29/2026-07-03)" do
      ev = event_of_kind(:confirmation)
      expect(described_class.verbs_for(ev)).to eq(%w[help])
    end

    it "offers ONLY `help` for a :thinking message" do
      ev = event_of_kind(:thinking)
      expect(described_class.verbs_for(ev)).to eq(%w[help])
    end

    it "offers ONLY `help` for an :echo message" do
      ev = event_of_kind(:echo)
      expect(described_class.verbs_for(ev)).to eq(%w[help])
    end

    it "offers ONLY `help` for an :error message" do
      ev = event_of_kind(:error)
      expect(described_class.verbs_for(ev)).to eq(%w[help])
    end

    it "offers `help` and `share` for a nil event (the generic event-less help page)" do
      expect(described_class.verbs_for(nil)).to match_array(%w[help share])
    end
  end

  # Regression (owner 2026-07-01): a message whose thinking indicator is still
  # spinning is NOT shareable — sharing it would capture a half-loaded state.
  describe "resolution gate (unresolved messages are not shareable)" do
    def thinking_for(event, resolved:)
      Event.create_with_position!(
        conversation:, turn:, kind: :thinking,
        payload: { "for_event_id" => event.id.to_s, "resolved" => resolved }
      )
    end

    it ".resolved? is true when the message has no linked thinking indicator" do
      expect(described_class.resolved?(event)).to be(true)
    end

    it ".resolved? is false while the linked thinking indicator is unresolved" do
      thinking_for(event, resolved: false)
      expect(described_class.resolved?(event)).to be(false)
    end

    it ".resolved? is true once the linked thinking indicator is resolved" do
      thinking_for(event, resolved: true)
      expect(described_class.resolved?(event)).to be(true)
    end

    it ".verbs_for offers ONLY `help` while the message is unresolved (share verbs withheld)" do
      thinking_for(event, resolved: false)
      expect(described_class.verbs_for(event)).to eq(%w[help])
    end

    it ".verbs_for offers `help` and `share` once the message resolves" do
      thinking_for(event, resolved: true)
      expect(described_class.verbs_for(event)).to match_array(%w[help share])
    end

    it "#call refuses `share` with the not_resolved error while unresolved" do
      thinking_for(event, resolved: false)
      result = handler.call(source_event: event, rest: "share", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.copy.share.not_resolved")
    end

    it "#call does NOT create a Share for an unresolved message" do
      thinking_for(event, resolved: false)
      expect {
        handler.call(source_event: event, rest: "share", conversation:)
      }.not_to change(Share, :count)
    end

    it "#call allows `help` even while the message is unresolved" do
      event_with_target = Event.create_with_position!(
        conversation:, turn:, kind: :system,
        payload: { "text" => "games!", "reply_handle" => "unres-help", "reply_target" => "game_list" }
      )
      thinking_for(event_with_target, resolved: false)
      result = handler.call(source_event: event_with_target, rest: "help", conversation:)
      # help bypasses the resolution gate — returns Append (not Error)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end
  end

  describe "#call — share verb" do
    it "mints a Share record" do
      expect {
        handler.call(source_event: event, rest: "share", conversation:)
      }.to change(Share, :count).by(1)
    end

    it "returns a Result::Append with consume: false" do
      result = handler.call(source_event: event, rest: "share", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to eq(false)
    end

    # The share message is now an html payload: the witty line with the URL as a
    # clickable <a target="_blank"> (action class) + a copy affordance.
    def share_body(result) = result.events.first[:payload]["body"].to_s
    def share_href(result) = share_body(result)[/href="([^"]+)"/, 1]

    it "returns an html :system event with the share URL as a clickable action-class link + copy widget" do
      result = handler.call(source_event: event, rest: "share", conversation:)
      expect(result.events.length).to eq(1)
      expect(result.events.first[:kind]).to eq(:system)
      payload = result.events.first[:payload]
      expect(payload["html"]).to be(true)
      expect(payload["body"]).to include("/share/")
      expect(payload["body"]).to include('target="_blank"')
      expect(payload["body"]).to include("pito-action-shimmer")
      expect(payload["body"]).to include("pito--clipboard")
    end

    it "mints the URL on the request origin when one is threaded through" do
      result = handler.call(source_event: event, rest: "share", conversation:, origin: "https://dev.pitomd.com")
      expect(share_body(result)).to include("https://dev.pitomd.com/share/")
    end

    it "falls back to PublicHosts.app_base when no origin is given" do
      allow(Pito::PublicHosts).to receive(:app_base).and_return("http://localhost:3027")
      result = handler.call(source_event: event, rest: "share", conversation:)
      expect(share_body(result)).to include("http://localhost:3027/share/")
    end

    it "is idempotent — calling share twice returns the same Share URL" do
      result1 = handler.call(source_event: event, rest: "share", conversation:)
      result2 = handler.call(source_event: event, rest: "share", conversation:)
      expect(share_href(result1)).to eq(share_href(result2))
      expect(Share.where(event:).count).to eq(1)
    end

    it "reuses the existing Share when called multiple times" do
      handler.call(source_event: event, rest: "share", conversation:)
      expect {
        handler.call(source_event: event, rest: "share", conversation:)
      }.not_to change(Share, :count)
    end
  end

  describe "#call — revoke verb" do
    context "when a Share exists for the event" do
      before { Share.create!(event:, conversation:) }

      it "enqueues RevokeShareJob" do
        expect {
          handler.call(source_event: event, rest: "revoke", conversation:)
        }.to have_enqueued_job(RevokeShareJob).with(event.id)
      end

      it "returns a Result::Append with consume: true" do
        result = handler.call(source_event: event, rest: "revoke", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Append)
        expect(result.consume).to eq(true)
      end

      it "returns a :system event with a revoke_ack message" do
        result = handler.call(source_event: event, rest: "revoke", conversation:)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["text"]).to be_present
      end
    end

    context "when NO Share exists for the event" do
      it "returns a Result::Error" do
        result = handler.call(source_event: event, rest: "revoke", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Error)
      end

      it "references the not_shared copy key" do
        result = handler.call(source_event: event, rest: "revoke", conversation:)
        expect(result.message_key).to eq("pito.copy.share.not_shared")
      end

      it "does NOT enqueue RevokeShareJob" do
        expect {
          handler.call(source_event: event, rest: "revoke", conversation:)
        }.not_to have_enqueued_job(RevokeShareJob)
      end
    end
  end

  describe "#call — unshare verb (alias for revoke)" do
    context "when a Share exists for the event" do
      before { Share.create!(event:, conversation:) }

      it "enqueues RevokeShareJob" do
        expect {
          handler.call(source_event: event, rest: "unshare", conversation:)
        }.to have_enqueued_job(RevokeShareJob).with(event.id)
      end

      it "returns a Result::Append with consume: true" do
        result = handler.call(source_event: event, rest: "unshare", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Append)
        expect(result.consume).to eq(true)
      end
    end

    context "when NO Share exists for the event" do
      it "returns a Result::Error" do
        result = handler.call(source_event: event, rest: "unshare", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Error)
      end

      it "references the not_shared copy key" do
        result = handler.call(source_event: event, rest: "unshare", conversation:)
        expect(result.message_key).to eq("pito.copy.share.not_shared")
      end

      it "does NOT enqueue RevokeShareJob" do
        expect {
          handler.call(source_event: event, rest: "unshare", conversation:)
        }.not_to have_enqueued_job(RevokeShareJob)
      end
    end
  end

  describe "#call — help verb" do
    before { Pito::FollowUp::Registry.register_all! }

    context "when the source event has a known reply_target with copy" do
      let(:help_event) do
        Event.create_with_position!(
          conversation:, turn:, kind: :system,
          payload: { "text" => "games!", "reply_handle" => "help-handle", "reply_target" => "game_list" }
        )
      end

      it "returns a Result::Append" do
        result = handler.call(source_event: help_event, rest: "help", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Append)
      end

      it "does NOT consume the source event (consume: false)" do
        result = handler.call(source_event: help_event, rest: "help", conversation:)
        expect(result.consume).to eq(false)
      end

      it "returns a single :system event containing the help page" do
        result = handler.call(source_event: help_event, rest: "help", conversation:)
        expect(result.events.length).to eq(1)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload]["html"]).to be(true)
        expect(result.events.first[:payload]["body"]).to include("pito-help-block")
      end
    end

    context "when the source event has no reply_target" do
      it "returns a Result::Error referencing help_unavailable" do
        result = handler.call(source_event: event, rest: "help", conversation:)
        expect(result).to be_a(Pito::FollowUp::Result::Error)
        expect(result.message_key).to eq("pito.copy.share.help_unavailable")
      end
    end
  end

  describe "#call — unknown verb" do
    it "returns a Result::Error" do
      result = handler.call(source_event: event, rest: "bogus", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end
  end
end
