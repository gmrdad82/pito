# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::MiniStatus::NotificationsComponent do
  describe "rendered output" do
    it "renders the ctrl+/ hint in a bold yellow span" do
      node = render_inline(described_class.new(count: 3))
      yellow = node.css("span.font-bold.text-yellow").first
      expect(yellow).to be_present
      expect(yellow.text).to eq("ctrl+/")
    end

    it "renders the count in a cyan-shimmer token span" do
      node = render_inline(described_class.new(count: 3))
      expect(node.css("span.pito-token-shimmer")).not_to be_empty
    end

    it "renders a singular count as '1*'" do
      node = render_inline(described_class.new(count: 1))
      expect(node.css("span.pito-token-shimmer").text).to eq("1*")
    end

    it "renders a plural count with the same '*' glyph" do
      node = render_inline(described_class.new(count: 5))
      expect(node.css("span.pito-token-shimmer").text).to eq("5*")
    end

    it "wraps the count in a clickable control that toggles notifications (same as ctrl+/)" do
      node    = render_inline(described_class.new(count: 2))
      control = node.css('[role="button"]').first
      expect(control).to be_present
      expect(control["data-action"]).to include("click->pito--notifications-count#toggle")
      expect(control["aria-label"]).to eq("Open notifications")
      # the shimmer token lives inside the clickable control
      expect(control.css("span.pito-token-shimmer")).not_to be_empty
    end

    it "renders inside an inline-flex gap-1 wrapper" do
      node = render_inline(described_class.new(count: 2))
      wrapper = node.css("span.inline-flex.items-center.gap-1").first
      expect(wrapper).not_to be_nil
    end
  end
end
