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

  describe "step labels" do
    it "passes copy step labels as a JSON array via data attribute" do
      node = render_inline(described_class.new(prefill: "", conversation_uuid: uuid))
      el   = node.css("[data-pito--games-search-i18n-step-labels-value]").first
      labels = JSON.parse(el["data-pito--games-search-i18n-step-labels-value"])
      expect(labels.length).to eq(5)
      expect(I18n.t("pito.copy.games.import.step1")).to include(labels[0])
      expect(I18n.t("pito.copy.games.import.step5")).to include(labels[4])
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

  describe "native block caret" do
    subject(:node) { render_inline(described_class.new(prefill: "", conversation_uuid: uuid)) }

    it "styles the search input with the native block caret (.pito-block-caret)" do
      input = node.css("input[data-pito--games-search-target='input']").first
      expect(input).to be_present
      expect(input["class"]).to include("pito-block-caret")
    end

    it "renders no bespoke caret/trail machinery" do
      expect(node.css("[data-controller~='pito--terminal-caret']")).to be_empty
      expect(node.css("[data-controller~='pito--cursor-trail']")).to be_empty
      expect(node.css("span.terminal-caret")).to be_empty
      expect(node.css("[data-pito--terminal-caret-target]")).to be_empty
      expect(node.css(".pito-caret-input")).to be_empty
    end
  end
end
