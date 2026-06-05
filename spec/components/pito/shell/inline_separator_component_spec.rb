# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::InlineSeparatorComponent do
  describe "rendered output" do
    subject(:node) { render_inline(described_class.new) }

    it "renders a span element" do
      expect(node.css("span")).not_to be_empty
    end

    it "contains the middot character" do
      expect(node.css("span").first.text).to eq("·")
    end

    it "applies the text-fg-faded class" do
      expect(node.css("span.text-fg-faded")).not_to be_empty
    end

    it "applies the mx-2 class" do
      expect(node.css("span.mx-2")).not_to be_empty
    end

    it "renders both required classes on a single span" do
      span = node.css("span").first
      expect(span["class"]).to include("text-fg-faded")
      expect(span["class"]).to include("mx-2")
    end
  end
end
