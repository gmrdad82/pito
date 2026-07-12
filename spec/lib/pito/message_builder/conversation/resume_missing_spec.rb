# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Conversation::ResumeMissing, type: :service do
  # Conversation.singleton is used so HandleGenerator can check existing handles;
  # the similar doubles only need to respond to #title — no DB required for them.
  let(:conversation) { Conversation.singleton }
  let(:name)         { "Awesome Run" }

  describe ".call" do
    # ── no similar conversations ─────────────────────────────────────────────

    context "with similar: []" do
      subject(:payload) { described_class.call(name: name, similar: [], conversation: conversation) }

      it "returns a hash with html: true" do
        expect(payload).to be_a(Hash)
        expect(payload["html"]).to be(true)
      end

      it "body is a non-empty HTML string" do
        expect(payload["body"]).to be_a(String)
        expect(payload["body"]).to be_present
      end

      it "body contains the /new <name> command" do
        expect(payload["body"]).to include("/new #{name}")
      end

      it "body carries pito--chat-prefill-submit-value (auto-submit on click)" do
        expect(payload["body"]).to include("pito--chat-prefill-submit-value")
      end

      it "is follow-up-able: reply_target is 'resume_missing'" do
        expect(payload["reply_target"]).to eq("resume_missing")
      end

      it "payload carries resume_name equal to the requested name" do
        expect(payload["resume_name"]).to eq(name)
      end

      it "payload carries a reply_handle" do
        expect(payload["reply_handle"]).to be_present
      end

      it "body does NOT include the suggestions intro section (text-fg-dim div absent)" do
        expect(payload["body"]).not_to include("text-fg-dim")
      end

      it "body does NOT include any /resume token" do
        expect(payload["body"]).not_to include("/resume ")
      end
    end

    # ── with similar conversations ───────────────────────────────────────────

    context "with similar: [double(title: 'Foo'), double(title: 'Bar')]" do
      let(:similar) { [ double(title: "Foo"), double(title: "Bar") ] }

      subject(:payload) do
        described_class.call(name: name, similar: similar, conversation: conversation)
      end

      it "body includes the suggestions_intro section (text-fg-dim div present)" do
        expect(payload["body"]).to include("text-fg-dim")
      end

      it "body includes a /resume Foo prefill token" do
        expect(payload["body"]).to include("/resume Foo")
      end

      it "body includes a /resume Bar prefill token" do
        expect(payload["body"]).to include("/resume Bar")
      end

      it "each suggestion token is a prefill+submit (pito--chat-prefill-submit-value present)" do
        expect(payload["body"]).to include("pito--chat-prefill-submit-value")
      end

      it "still includes the /new <name> create token" do
        expect(payload["body"]).to include("/new #{name}")
      end

      it "reply_target is still 'resume_missing'" do
        expect(payload["reply_target"]).to eq("resume_missing")
      end

      it "resume_name is still the requested name" do
        expect(payload["resume_name"]).to eq(name)
      end
    end
  end
end
