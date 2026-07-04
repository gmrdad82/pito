# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::Chatbox::NameComponent do
  it "always renders the stable slot id (so a rename broadcast can target it)" do
    node = render_inline(described_class.new(title: nil))
    expect(node.at_css("##{described_class::SLOT_ID}")).to be_present
  end

  context "when named" do
    it "renders the context-meter name (13.39 — the name lives in the meter header)" do
      node = render_inline(described_class.new(title: "Pragmata Run"))
      name = node.at_css(".pito-context-meter__name")
      expect(name).to be_present
      expect(name.text.strip).to eq("Pragmata Run")
      expect(name[:class]).to include("text-fg-dim")
    end
  end

  context "when Unnamed (nil/blank title)" do
    it "renders the slot but no name" do
      node = render_inline(described_class.new(title: nil))
      expect(node.css(".pito-context-meter__name")).to be_empty
    end

    it "treats a blank string as unnamed" do
      node = render_inline(described_class.new(title: "  "))
      expect(node.css(".pito-context-meter__name")).to be_empty
    end
  end
end
