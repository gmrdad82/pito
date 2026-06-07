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

  it "renders cyan keys in an auto-sizing aligned grid column" do
    node = render_inline(described_class.new(sections: sections))
    keys = node.css("span.text-cyan").map(&:text)
    expect(keys).to eq([ "/help", "/logout", "/config google" ])
    # Each section uses a max-content grid so the command column auto-sizes to
    # the widest entry (no fixed width that overflowed long commands).
    grids = node.css("div.grid")
    expect(grids).not_to be_empty
    grids.each { |g| expect(g["class"]).to include("grid-cols-[max-content_1fr]") }
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
