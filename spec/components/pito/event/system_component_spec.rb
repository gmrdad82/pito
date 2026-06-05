# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::SystemComponent do
  describe "typewriter hook — plain-text body" do
    subject(:node) { render_inline(described_class.new(payload: { body: "Hello world" })) }

    it "annotates the body span with data-controller including pito--typewriter" do
      span = node.css("span.text-fg[data-controller]").first
      expect(span).not_to be_nil
      expect(span["data-controller"]).to include("pito--typewriter")
    end

    it "sets data-pito--typewriter-target='body' on the body span" do
      span = node.css("span.text-fg[data-pito--typewriter-target='body']").first
      expect(span).not_to be_nil
    end

    it "includes the body text in the span" do
      span = node.css("span.text-fg[data-pito--typewriter-target='body']").first
      expect(span.text).to include("Hello world")
    end
  end

  describe "typewriter hook — html body (html: true)" do
    subject(:node) { render_inline(described_class.new(payload: { body: "<b>bold</b>", html: true })) }

    it "does NOT add the typewriter controller when body is html" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
    end

    it "renders the raw html in a plain text-fg span" do
      span = node.css("span.text-fg").first
      expect(span).not_to be_nil
    end
  end

  describe "typewriter hook — empty body" do
    subject(:node) { render_inline(described_class.new(payload: { body: nil })) }

    it "does NOT add the typewriter controller when body is nil" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
    end
  end

  describe "sections mode — plain-text body" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "Sections body text",
        sections: [ { title: "Section 1", rows: [] } ]
      }))
    end

    it "adds pito--typewriter controller to the prose wrapper div in sections mode" do
      wrapper = node.css("div[data-controller~='pito--typewriter']").first
      expect(wrapper).not_to be_nil
      span = wrapper.css("span[data-pito--typewriter-target='body']").first
      expect(span).not_to be_nil
      expect(span.text).to include("Sections body text")
    end
  end

  describe "sections mode — html body" do
    subject(:node) do
      render_inline(described_class.new(payload: {
        body: "<em>rich</em>",
        html: true,
        sections: [ { title: "Section 1", rows: [] } ]
      }))
    end

    it "does NOT add typewriter controller in sections mode when html" do
      expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
    end
  end

  describe "SystemFollowUpComponent (inherits system template via enhanced)" do
    it "renders pito--typewriter on plain-text body" do
      node = render_inline(Pito::Event::SystemFollowUpComponent.new(payload: { body: "Follow up text" }))
      expect(node.css("[data-controller~='pito--typewriter']")).not_to be_empty
    end
  end
end
