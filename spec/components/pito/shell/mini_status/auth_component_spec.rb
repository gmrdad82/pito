# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::MiniStatus::AuthComponent do
  describe "default state" do
    it "defaults to unauthenticated (state: false)" do
      node = render_inline(described_class.new)
      expect(node.to_html).to include("○ auth")
    end
  end

  describe "state: false (anonymous)" do
    it "renders the anonymous label in a red span" do
      node = render_inline(described_class.new(state: false))
      expect(node.css("span.text-red").text).to include("○ auth")
    end

    it "does not render the authenticated disc alone" do
      node = render_inline(described_class.new(state: false))
      # The authenticated state renders only "●"; unauthenticated renders "○ auth"
      expect(node.css("span.text-green")).to be_empty
    end
  end

  describe "state: true (authenticated)" do
    it "renders only the green disc ● without the 'auth' word" do
      node = render_inline(described_class.new(state: true))
      green_span = node.css("span.text-green").first
      expect(green_span).to be_present
      expect(green_span.text.strip).to eq("●")
    end

    it "does not render the 'auth' word when authenticated" do
      node = render_inline(described_class.new(state: true))
      expect(node.to_html).not_to include("auth")
    end

    it "does not render the anonymous label" do
      node = render_inline(described_class.new(state: true))
      expect(node.to_html).not_to include("○ auth")
    end
  end
end
