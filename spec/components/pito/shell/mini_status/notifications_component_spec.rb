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

    it "renders the count as dim, non-clickable text (one trailing tone)" do
      node = render_inline(described_class.new(count: 3))
      expect(node.to_html).to include("text-fg-dim")
      expect(node.css('[role="button"]')).to be_empty
    end

    it "renders a singular count as '1*'" do
      expect(render_inline(described_class.new(count: 1)).text).to include("1")
    end

    it "renders a plural count with the same '*' glyph" do
      expect(render_inline(described_class.new(count: 5)).text).to include("5")
    end

    it "is NOT clickable — no toggle action (open notifications via ctrl+/)" do
      node = render_inline(described_class.new(count: 2))
      expect(node.css('[role="button"]')).to be_empty
      expect(node.to_html).not_to include("pito--notifications-count#toggle")
    end

    it "keeps the new-notification chime controller on the wrapper" do
      node = render_inline(described_class.new(count: 2))
      expect(node.css('[data-controller="pito--notifications-count"]')).not_to be_empty
    end

    it "renders inside an inline-flex gap-1 wrapper" do
      node = render_inline(described_class.new(count: 2))
      expect(node.css("span.inline-flex.items-center.gap-1").first).not_to be_nil
    end
  end
end
