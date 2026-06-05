# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Keybinding::TableComponent do
  let(:sections) do
    [
      {
        title: "GENERAL",
        rows: [
          { key: "/help",   value: "Show this message" },
          { key: "/logout", value: "Log out" }
        ]
      },
      {
        title: "CONFIG",
        rows: [
          { key: "/config google", value: "Google OAuth credentials" }
        ]
      }
    ]
  end

  it "renders yellow section titles" do
    node = render_inline(described_class.new(sections: sections))
    titles = node.css(".text-yellow.font-bold").map(&:text)
    expect(titles).to eq([ "GENERAL", "CONFIG" ])
  end

  it "renders cyan keys with fixed width" do
    node = render_inline(described_class.new(sections: sections))
    keys = node.css("span.text-cyan").map(&:text)
    expect(keys).to eq([ "/help", "/logout", "/config google" ])
    # Every key span carries the fixed width class
    node.css("span.text-cyan").each do |span|
      expect(span["class"]).to include("w-44")
    end
  end

  it "renders muted values aligned to the same offset" do
    node = render_inline(described_class.new(sections: sections))
    values = node.css("span.text-fg-dim").map(&:text)
    expect(values).to eq([ "Show this message", "Log out", "Google OAuth credentials" ])
  end

  it "renders nothing when sections is empty" do
    node = render_inline(described_class.new(sections: []))
    expect(node.text.strip).to be_empty
  end
end
