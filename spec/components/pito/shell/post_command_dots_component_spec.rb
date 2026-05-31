# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::PostCommandDotsComponent do
  describe "rendered output" do
    it "renders the comet container div" do
      node = render_inline(described_class.new)
      expect(node.css("div.pito-comet")).not_to be_empty
    end

    it "renders exactly 8 dot elements" do
      node = render_inline(described_class.new)
      expect(node.css("div.pito-comet div.dot").length).to eq(8)
    end

    it "embeds the comet animation CSS" do
      node = render_inline(described_class.new)
      html = node.to_html
      expect(html).to include("pito-comet")
      expect(html).to include("pito-c1")
    end

    it "includes the keyframe animation definitions" do
      node = render_inline(described_class.new)
      html = node.to_html
      expect(html).to include("@keyframes pito-c1")
      expect(html).to include("@keyframes pito-c8")
    end

    it "renders the style block before the comet div" do
      node = render_inline(described_class.new)
      html = node.to_html
      style_pos = html.index("<style>")
      comet_pos = html.index("pito-comet")
      expect(style_pos).not_to be_nil
      expect(comet_pos).not_to be_nil
      expect(style_pos).to be < comet_pos
    end
  end
end
