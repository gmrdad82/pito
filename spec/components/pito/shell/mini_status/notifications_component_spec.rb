# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::MiniStatus::NotificationsComponent do
  describe "rendered output" do
    it "renders the count in a cyan span" do
      node = render_inline(described_class.new(count: 3))
      expect(node.css("span.text-cyan")).not_to be_empty
    end

    it "renders a singular count using the notifications_count i18n key" do
      node = render_inline(described_class.new(count: 1))
      expect(node.css("span.text-cyan").text).to eq("(1)")
    end

    it "renders a plural count using the notifications_count i18n key" do
      node = render_inline(described_class.new(count: 5))
      expect(node.css("span.text-cyan").text).to eq("(5)")
    end
  end
end
