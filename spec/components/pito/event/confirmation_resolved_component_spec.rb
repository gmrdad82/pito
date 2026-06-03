# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::ConfirmationResolvedComponent do
  let(:outcome_text) { "Disconnected from @gmrdad82. Deleted 42 videos." }

  subject(:node) { render_inline(described_class.new(outcome_text:)) }

  describe "outer container" do
    it "has border-t class" do
      div = node.css("div").first
      expect(div["class"]).to include("border-t")
    end

    it "has border-line-faded class" do
      div = node.css("div").first
      expect(div["class"]).to include("border-line-faded")
    end

    it "has mt-1.5 and pt-1.5 spacing classes" do
      div = node.css("div").first
      expect(div["class"]).to include("mt-1.5")
      expect(div["class"]).to include("pt-1.5")
    end
  end

  describe "outcome text" do
    it "renders the outcome text inside span.text-fg" do
      expect(node.css("span.text-fg").first&.text).to include(outcome_text)
    end

    it "span.text-fg is inside the border-t div" do
      div = node.css("div.border-t").first
      expect(div.css("span.text-fg")).not_to be_empty
    end
  end

  describe "with different outcome texts" do
    it "renders a cancelled outcome text correctly" do
      cancelled_text = "Alright, leaving @gmrdad82 connected."
      node = render_inline(described_class.new(outcome_text: cancelled_text))
      expect(node.css("span.text-fg").first.text).to include("leaving @gmrdad82 connected")
    end

    it "renders a zero-deletion outcome correctly" do
      zero_text = "Disconnected from @gmrdad82. No videos to delete."
      node = render_inline(described_class.new(outcome_text: zero_text))
      expect(node.css("span.text-fg").first.text).to include("No videos to delete")
    end

    it "renders a generic error outcome correctly" do
      error_text = "Something went wrong. The action may be partially completed."
      node = render_inline(described_class.new(outcome_text: error_text))
      expect(node.css("span.text-fg").first.text).to include("Something went wrong")
    end
  end
end
