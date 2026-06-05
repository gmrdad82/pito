# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::EnhancedComponent do
  describe "typewriter hook — plain-text body" do
    subject(:node) { render_inline(described_class.new(payload: { body: "Enhanced response" })) }

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
      expect(span.text).to include("Enhanced response")
    end
  end

  describe "typewriter hook — html body (html: true)" do
    subject(:node) { render_inline(described_class.new(payload: { body: "<em>italic</em>", html: true })) }

    it "does NOT add the typewriter controller when body is html" do
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
end
