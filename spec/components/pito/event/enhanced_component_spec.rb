# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::EnhancedComponent do
  describe "typewriter hook — plain-text body" do
    subject(:node) { render_inline(described_class.new(payload: { body: "Enhanced response" })) }

    it "wraps content in a div with data-controller='pito--typewriter'" do
      wrapper = node.css("div[data-controller~='pito--typewriter']").first
      expect(wrapper).not_to be_nil
    end

    it "sets data-pito--typewriter-target='body' on the body span inside the wrapper" do
      span = node.css("[data-controller~='pito--typewriter'] span[data-pito--typewriter-target='body']").first
      expect(span).not_to be_nil
    end

    it "includes the body text in the body span" do
      span = node.css("span.text-fg[data-pito--typewriter-target='body']").first
      expect(span).not_to be_nil
      expect(span.text).to include("Enhanced response")
    end
  end

  describe "typewriter hook — html body (html: true)" do
    subject(:node) { render_inline(described_class.new(payload: { body: "<em>italic</em>", html: true })) }

    it "mounts the typewriter controller so the html card reveals (visibility toggle)" do
      expect(node.css("div[data-controller~='pito--typewriter']").first).not_to be_nil
    end

    it "tags the html card content as an htmlProse target" do
      wrapper = node.css("div[data-controller~='pito--typewriter']").first
      expect(wrapper.css("[data-pito--typewriter-target='htmlProse']").first).not_to be_nil
    end
  end

  describe "typewriter hook — html body, CONSUMED (no re-reveal on replace_event)" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "<em>italic</em>", html: true,
        reply_handle: "h", reply_target: "game_detail", reply_consumed: true
      }))
    end

    it "does NOT mount the typewriter controller once consumed" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
    end
  end

  describe "typewriter hook — empty body" do
    subject(:node) { render_inline(described_class.new(payload: { body: nil })) }

    it "does NOT add the typewriter controller when body is nil" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
    end
  end

  describe "EnhancedFollowUpComponent (inherits enhanced template)" do
    it "renders pito--typewriter on plain-text body" do
      node = render_inline(Pito::Event::EnhancedFollowUpComponent.new(payload: { body: "Follow up enhanced" }))
      expect(node.css("[data-controller~='pito--typewriter']")).not_to be_empty
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
