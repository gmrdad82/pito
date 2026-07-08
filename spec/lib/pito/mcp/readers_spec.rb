# frozen_string_literal: true

require "rails_helper"

# Contract for Pito::Mcp::Readers — the two persisted-row reader tools. They read
# `source: "app"` conversations/events only (the MCP anchor never appears) and
# project via EventText. No Router dispatch, no writes.
RSpec.describe Pito::Mcp::Readers do
  # Append an event to a conversation at the next position.
  def add_event(conversation, kind:, payload:, position:)
    turn = create(:turn, conversation: conversation)
    create(:event, conversation: conversation, turn: turn, kind: kind, payload: payload, position: position)
  end

  describe ".call routing" do
    it "raises UnknownTool for an unknown reader name" do
      expect { described_class.call("pito_nope") }.to raise_error(Pito::Mcp::Executor::UnknownTool)
    end
  end

  describe "pito_conversations" do
    it "reports 'no conversations' when there are none" do
      result = described_class.call("pito_conversations")
      expect(result.is_error).to be(false)
      expect(result.text).to match(/no conversations/i)
    end

    it "lists app conversations with uuid + title, and never the mcp anchor" do
      anchor = Conversation.mcp_anchor
      conv   = create(:conversation, title: "My gaming channel")

      text = described_class.call("pito_conversations").text

      expect(text).to include(conv.uuid, "My gaming channel")
      expect(text).not_to include(anchor.uuid)
    end
  end

  describe "pito_messages" do
    let(:conversation) { create(:conversation, title: "Session One") }

    before do
      add_event(conversation, kind: "echo",   payload: { "text" => "show vid #3" }, position: 1)
      add_event(conversation, kind: "thinking", payload: { "text" => "…" }, position: 2)  # excluded
      add_event(conversation, kind: "system", payload: { "text" => "Here is vid #3." }, position: 3)
    end

    it "defaults to the latest active conversation, newest last, role-prefixed" do
      text = described_class.call("pito_messages", {}).text
      expect(text).to include("Session One")
      expect(text).to include("you: show vid #3")
      expect(text).to include("pito: Here is vid #3.")
      expect(text.index("you: show vid #3")).to be < text.index("pito: Here is vid #3.")
    end

    it "excludes the thinking spinner (a non-readable kind)" do
      expect(described_class.call("pito_messages", {}).text).not_to include("…")
    end

    it "reads a specific conversation by uuid" do
      other = create(:conversation, title: "Session Two")
      add_event(other, kind: "system", payload: { "text" => "Two speaking." }, position: 1)

      text = described_class.call("pito_messages", { "conversation_uuid" => other.uuid }).text
      expect(text).to include("Session Two", "Two speaking.")
      expect(text).not_to include("show vid #3")
    end

    it "honours the limit, keeping the last N (newest last)" do
      15.times { |i| add_event(conversation, kind: "system", payload: { "text" => "msg #{i}" }, position: 10 + i) }
      text = described_class.call("pito_messages", { "limit" => 2 }).text
      expect(text.scan(/^(?:you|pito):/).size).to eq(2)  # exactly two message lines
      expect(text).to include("msg 13", "msg 14")        # the two newest kept
      expect(text).not_to include("msg 12")              # older trimmed
    end

    it "serializes a FILLED analytics payload in its CURRENT state (de-HTML'd)" do
      ready = create(:conversation, title: "Filled")
      add_event(ready, kind: "enhanced",
                payload: { "body" => "<div>Views: 1234</div>", "html" => true, "analytics" => { "status" => "ready" } },
                position: 1)
      text = described_class.call("pito_messages", { "conversation_uuid" => ready.uuid }).text
      expect(text).to include("Views: 1234")
      expect(text).not_to include("<div>")
    end

    it "errors for an unknown uuid" do
      result = described_class.call("pito_messages", { "conversation_uuid" => "does-not-exist" })
      expect(result.is_error).to be(true)
      expect(result.text).to match(/no conversation found/i)
    end

    it "never reads the mcp anchor's events" do
      anchor = Conversation.mcp_anchor
      add_event(anchor, kind: "system", payload: { "text" => "anchor leak" }, position: 1)
      # default (no uuid) resolves to the latest APP conversation, never the anchor
      expect(described_class.call("pito_messages", {}).text).not_to include("anchor leak")
      # and the anchor is not addressable by uuid through the app-scoped lookup
      result = described_class.call("pito_messages", { "conversation_uuid" => anchor.uuid })
      expect(result.is_error).to be(true)
    end
  end
end
