# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Share::UnfoldHintComponent, type: :component do
  subject(:node) { render_inline(described_class.new(conversation_url: "/chat/abc-123")) }

  it "renders the 'c to chat' hint (shown when unfocused)" do
    chat = node.at_css("[data-pito--share-unfold-target='chatHint']")
    expect(chat).to be_present
    expect(chat.text).to include("to chat")
  end

  it "renders the 'Enter to unfold' hint, hidden by default" do
    unfold = node.at_css("[data-pito--share-unfold-target='unfoldHint']")
    expect(unfold).to be_present
    expect(unfold["class"]).to include("hidden")
    expect(unfold.text).to include("to unfold")
  end

  it "renders Enter as an action-shimmer LINK to the conversation" do
    link = node.at_css("a.pito-action-shimmer[data-pito--share-unfold-target='link']")
    expect(link).to be_present
    expect(link["href"]).to eq("/chat/abc-123")
    expect(link.text).to eq("Enter")
  end
end
