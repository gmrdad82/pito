# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Sidebar::GamesImport::Component do
  let(:uuid) { "test-uuid-1234" }

  describe "search input" do
    it "renders an <input> element" do
      node = render_inline(described_class.new(prefill: "", conversation_uuid: uuid))
      expect(node.css("input[type='text']")).not_to be_empty
    end

    it "mounts the pito--games-search Stimulus controller" do
      node = render_inline(described_class.new(prefill: "", conversation_uuid: uuid))
      expect(node.css("[data-controller='pito--games-search']")).not_to be_empty
    end

    it "passes the conversation UUID as a data-value attribute" do
      node = render_inline(described_class.new(prefill: "", conversation_uuid: uuid))
      el   = node.css("[data-pito--games-search-conversation-uuid-value]").first
      expect(el["data-pito--games-search-conversation-uuid-value"]).to eq(uuid)
    end
  end

  describe "prefill" do
    it "pre-populates the input value when prefill is given" do
      node = render_inline(described_class.new(prefill: "Hollow Knight", conversation_uuid: uuid))
      input = node.css("input[type='text']").first
      expect(input["value"]).to eq("Hollow Knight")
    end

    it "passes the prefill string to the controller value attribute" do
      node = render_inline(described_class.new(prefill: "Celeste", conversation_uuid: uuid))
      el   = node.css("[data-pito--games-search-prefill-value]").first
      expect(el["data-pito--games-search-prefill-value"]).to eq("Celeste")
    end

    it "renders an empty input when prefill is blank" do
      node = render_inline(described_class.new(prefill: "", conversation_uuid: uuid))
      input = node.css("input[type='text']").first
      expect(input["value"].to_s).to be_empty
    end
  end

  describe "targets" do
    it "renders the results target element" do
      node = render_inline(described_class.new(prefill: "", conversation_uuid: uuid))
      expect(node.css("[data-pito--games-search-target='results']")).not_to be_empty
    end

    it "renders the status target element" do
      node = render_inline(described_class.new(prefill: "", conversation_uuid: uuid))
      expect(node.css("[data-pito--games-search-target='status']")).not_to be_empty
    end

    it "renders the input target element" do
      node = render_inline(described_class.new(prefill: "", conversation_uuid: uuid))
      expect(node.css("[data-pito--games-search-target='input']")).not_to be_empty
    end
  end

  describe "shimmer indicator" do
    it "renders the shimmer target element" do
      node = render_inline(described_class.new(prefill: "", conversation_uuid: uuid))
      expect(node.css("[data-pito--games-search-target='shimmer']")).not_to be_empty
    end

    it "renders a .pito-shimmer span inside the shimmer target (via ShimmerTextComponent)" do
      node = render_inline(described_class.new(prefill: "", conversation_uuid: uuid))
      shimmer_p = node.css("[data-pito--games-search-target='shimmer']").first
      expect(shimmer_p.css("span.pito-shimmer")).not_to be_empty
    end

    it "renders the shimmer target hidden by default" do
      node = render_inline(described_class.new(prefill: "", conversation_uuid: uuid))
      shimmer_p = node.css("[data-pito--games-search-target='shimmer']").first
      expect(shimmer_p["class"]).to include("hidden")
    end
  end
end
