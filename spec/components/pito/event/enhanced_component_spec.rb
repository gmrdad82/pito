# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::EnhancedComponent do
  describe "instant render — plain-text body (item 18: no typewriter)" do
    subject(:node) { render_inline(described_class.new(payload: { body: "Enhanced response" })) }

    it "renders the body instantly with no typewriter wiring" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
      expect(node.css("[data-pito--typewriter-target]")).to be_empty
      span = node.css("span.text-fg").first
      expect(span.text).to include("Enhanced response")
    end
  end

  describe "instant render — html body (html: true)" do
    subject(:node) { render_inline(described_class.new(payload: { body: "<em>italic</em>", html: true })) }

    it "renders the html card instantly with no typewriter wiring" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
      expect(node.css("[data-pito--typewriter-target]")).to be_empty
      expect(node.css("em").text).to eq("italic")
    end
  end

  describe "EnhancedFollowUpComponent (inherits enhanced template)" do
    it "renders a plain-text body instantly with no typewriter" do
      node = render_inline(Pito::Event::EnhancedFollowUpComponent.new(payload: { body: "Follow up enhanced" }))
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
      expect(node.text).to include("Follow up enhanced")
    end
  end

  # Enhanced now shares SystemComponent's full template (the stripped enhanced
  # template was removed), so an :enhanced payload carrying table_rows renders
  # the table — previously it was silently dropped (e.g. show-game linked vids).
  describe "table rendering parity with :system" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body:          "Linked vids",
        table_heading: [ "#", "Title" ],
        table_rows:    [ { cells: [ { text: "#1" }, { text: "Boss Fight" } ] } ]
      }))
    end

    it "renders the data-grid table" do
      expect(node.css(".pito-data-grid")).not_to be_empty
    end

    it "renders the row cell content" do
      expect(node.to_html).to include("Boss Fight")
    end
  end
end
