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

    it "renders the count in a cyan span" do
      node = render_inline(described_class.new(count: 3))
      expect(node.css("span.text-cyan")).not_to be_empty
    end

    it "renders a singular count as '1 notif'" do
      node = render_inline(described_class.new(count: 1))
      expect(node.css("span.text-cyan").text).to eq("1 notif")
    end

    it "renders a plural count as 'N notifs'" do
      node = render_inline(described_class.new(count: 5))
      expect(node.css("span.text-cyan").text).to eq("5 notifs")
    end

    it "renders inside an inline-flex gap-1 wrapper" do
      node = render_inline(described_class.new(count: 2))
      wrapper = node.css("span.inline-flex.items-center.gap-1").first
      expect(wrapper).not_to be_nil
    end
  end
end
