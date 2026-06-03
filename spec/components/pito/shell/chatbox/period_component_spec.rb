# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::Chatbox::PeriodComponent do
  describe "label text" do
    it "renders the i18n label 'period'" do
      node = render_inline(described_class.new(period: "7d"))
      expect(node.to_html).to include("period")
    end
  end

  describe "period value" do
    it "renders the period value in a span.text-cyan" do
      node = render_inline(described_class.new(period: "7d"))
      cyan_texts = node.css("span.text-cyan").map(&:text)
      expect(cyan_texts).to include("7d")
    end

    it "applies ml-2 class to the value span" do
      node = render_inline(described_class.new(period: "7d"))
      cyan_span = node.css("span.text-cyan").first
      expect(cyan_span["class"]).to include("ml-2")
    end
  end

  describe "various period strings" do
    [ [ "7d", "7d" ], [ "30d", "30d" ], [ "1h", "1h" ] ].each do |period, expected|
      it "renders '#{expected}' correctly" do
        node = render_inline(described_class.new(period: period))
        expect(node.css("span.text-cyan").map(&:text)).to include(expected)
      end
    end
  end
end
