# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::MiniStatus::AuthComponent do
  describe "default state" do
    it "defaults to unauthenticated (state: false)" do
      node = render_inline(described_class.new)
      expect(node.css("svg.pito-conn-icon--lock")).not_to be_empty
      expect(node.text).to include("tarnished")
    end
  end

  describe "state: false (anonymous)" do
    it "renders the red LOCK icon and the red anonymous label" do
      node = render_inline(described_class.new(state: false))
      dot = node.css("span#pito-conn-dot").first
      expect(dot["class"]).to include("text-red")
      expect(dot.css("svg.pito-conn-icon--lock")).not_to be_empty
      expect(dot.css("svg.pito-conn-icon--cable")).to be_empty
      expect(node.css("span.text-red").text).to include("tarnished")
    end
  end

  describe "state: true (authenticated)" do
    it "carries both auth icons, starts CONNECTING (plug-zap), and shows the dim tag" do
      allow(Pito::Version).to receive(:suffix).and_return("dev")
      node = render_inline(described_class.new(state: true))
      dot = node.css("span#pito-conn-dot").first
      expect(dot["data-state"]).to eq("connecting")
      expect(dot["data-authenticated"]).to eq("true")
      expect(dot.css("svg.pito-conn-icon--plug.text-orange")).not_to be_empty
      expect(dot.css("svg.pito-conn-icon--cable.text-green")).not_to be_empty
      # The payload act (owner 2026-07-13): the red pen + its ink trail,
      # both pathLength-normalized duplicates of the cable's long run.
      expect(dot.css("path.pito-cable-dot[pathLength]")).not_to be_empty
      expect(dot.css("path.pito-cable-fill[pathLength]")).not_to be_empty
      expect(node.css("span.text-fg-dim").text).to include("dev")
    end

    it "does not render the anonymous label" do
      node = render_inline(described_class.new(state: true))
      expect(node.to_html).not_to include("tarnished")
    end
  end

  # G87: the suffix span is the bar's DEDICATED app-version slot — the cable
  # heartbeat (pito--version-watch) writes the server's version into it live.
  describe "the version slot (G87)" do
    it "the label span carries the stable slot id and the tag" do
      allow(Pito::Version).to receive(:suffix).and_return("1.1.1")
      node = render_inline(described_class.new(state: true))
      slot = node.css("span##{described_class::VERSION_SLOT_ID}").first
      expect(slot).to be_present
      expect(slot.text).to include("1.1.1")
    end

    it "renders the neutral fallback when the build carries no tag" do
      allow(Pito::Version).to receive(:suffix).and_return(nil)
      node = render_inline(described_class.new(state: true))
      expect(node.text).to include("pito")
    end

    it "renders no slot when unauthenticated" do
      node = render_inline(described_class.new(state: false))
      expect(node.css("span##{described_class::VERSION_SLOT_ID}")).to be_empty
    end
  end
end
