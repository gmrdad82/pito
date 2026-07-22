# frozen_string_literal: true

require "rails_helper"

# Unit spec — calls the uniform dispatch contract directly
# (Pito::Chat::Handlers::Visit.call(kwargs:, context:)), the same contract
# spec/dispatch/handler_contract_spec.rb pins for every chat verb. `visit` has
# no `chat:` block in config/pito/tools.yml yet (a later task wires that, plus
# the reply.targets delegation this handler's follow-up branch expects), so
# these specs build the message/context by hand rather than routing through
# Pito::Dispatch::Router.
RSpec.describe Pito::Chat::Handlers::Visit do
  let!(:channel) { create(:channel, handle: "@pito", title: "Pito Channel") }
  let!(:video)   { create(:video, channel: channel, title: "Boss Rush") }

  def visit(raw)
    message = Pito::Chat::Message.new(tool: :visit, body_tokens: [], kind: :new_turn, raw: raw)
    context = Pito::Dispatch::Context.new(message: message, conversation: Conversation.singleton)
    described_class.call(kwargs: {}, context: context)
  end

  # Mirrors what Pito::Dispatch::Router actually threads on a reply: `kwargs`
  # IS `follow_up.bound` (Pito::Dispatch::Router#bound_kwargs).
  def visit_reply(bound)
    source_event = instance_double("Event", payload: {})
    follow_up    = Pito::Chat::FollowUpContext.new(source_event: source_event, rest: "", bound: bound)
    context      = Pito::Dispatch::Context.new(message: nil, conversation: Conversation.singleton, follow_up: follow_up)
    described_class.call(kwargs: bound, context: context)
  end

  def payload_of(result)
    result.events.first[:payload]
  end

  # ── Typed-chat forms ───────────────────────────────────────────────────────────

  describe "vid <id> <destination>" do
    it "opens the vid's YouTube page for a youtube destination" do
      result  = visit("visit vid #{video.id} youtube")
      payload = payload_of(result)

      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(payload["video_id"]).to eq(video.id)
      expect(payload["visit_destination"]).to eq("youtube")
    end

    it "opens the vid's Studio page for a studio destination" do
      result  = visit("visit vid #{video.id} studio")
      payload = payload_of(result)

      expect(payload["video_id"]).to eq(video.id)
      expect(payload["visit_destination"]).to eq("studio")
    end

    it "returns not_found for an unknown vid id" do
      result = visit("visit vid 999999 youtube")

      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.visit.errors.not_found")
    end
  end

  describe "channel <id|@handle> <destination>" do
    it "resolves the channel by @handle" do
      result  = visit("visit channel @pito studio")
      payload = payload_of(result)

      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(payload["channel_id"]).to eq(channel.id)
      expect(payload["visit_destination"]).to eq("studio")
    end

    it "resolves the channel by numeric id" do
      result  = visit("visit channel #{channel.id} youtube")
      payload = payload_of(result)

      expect(payload["channel_id"]).to eq(channel.id)
      # Channel visit payloads keep the LEGACY "channel" value for a youtube destination.
      expect(payload["visit_destination"]).to eq("channel")
    end

    it "returns not_found for an unknown @handle" do
      result = visit("visit channel @unknown studio")

      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.visit.errors.not_found")
    end
  end

  describe "bare <destination> (sole-channel idiom)" do
    it "resolves the sole channel for a bare studio destination" do
      result  = visit("visit studio")
      payload = payload_of(result)

      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(payload["channel_id"]).to eq(channel.id)
      expect(payload["visit_destination"]).to eq("studio")
    end

    it "accepts the yt synonym, mapped to the legacy channel destination" do
      result  = visit("visit yt")
      payload = payload_of(result)

      expect(payload["channel_id"]).to eq(channel.id)
      expect(payload["visit_destination"]).to eq("channel")
    end

    context "with more than one channel connected" do
      let!(:other_channel) { create(:channel, handle: "@other") }

      it "still returns needs_destination for a bare destination (ambiguous)" do
        result = visit("visit studio")

        expect(result).to be_a(Pito::Chat::Result::Error)
        expect(result.message_key).to eq("pito.chat.visit.errors.needs_destination")
      end
    end
  end

  describe "needs_destination" do
    it "returns needs_destination when no recognizable destination is present" do
      result = visit("visit foo")

      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.visit.errors.needs_destination")
    end

    it "returns needs_destination when a subject is named but no destination follows" do
      result = visit("visit vid #{video.id}")

      expect(result).to be_a(Pito::Chat::Result::Error)
      expect(result.message_key).to eq("pito.chat.visit.errors.needs_destination")
    end
  end

  # ── Reply path (bound kwargs) ───────────────────────────────────────────────────

  describe "follow-up (bound kwargs)" do
    it "visits the bound video ref at its bound destination" do
      result  = visit_reply(ref: video, destination: "youtube")
      payload = payload_of(result)

      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(payload["video_id"]).to eq(video.id)
      expect(payload["visit_destination"]).to eq("youtube")
    end

    it "visits the bound channel ref, mapping the bound youtube destination to the legacy :channel value" do
      result  = visit_reply(ref: channel, destination: "youtube")
      payload = payload_of(result)

      expect(result).to be_a(Pito::Chat::Result::Ok)
      expect(payload["channel_id"]).to eq(channel.id)
      expect(payload["visit_destination"]).to eq("channel")
    end

    it "keeps studio as studio for a bound channel ref" do
      result  = visit_reply(ref: channel, destination: "studio")
      payload = payload_of(result)

      expect(payload["channel_id"]).to eq(channel.id)
      expect(payload["visit_destination"]).to eq("studio")
    end
  end

  # ── Copy keys ────────────────────────────────────────────────────────────────

  describe "copy" do
    it "renders the tool description" do
      expect(Pito::Copy.render(described_class.description_key)).to be_present
    end

    it "renders both error keys" do
      expect(Pito::Copy.render("pito.chat.visit.errors.needs_destination")).to be_present
      expect(Pito::Copy.render("pito.chat.visit.errors.not_found", ref: "5")).to be_present
    end
  end
end
