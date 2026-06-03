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

    it "does not render the authenticated label" do
      node = render_inline(described_class.new(state: false))
      expect(node.to_html).not_to include("● auth")
    end
  end

  describe "state: true (authenticated)" do
    it "renders the authenticated label in a green span" do
      node = render_inline(described_class.new(state: true))
      expect(node.css("span.text-green").text).to include("● auth")
    end

    it "does not render the anonymous label" do
      node = render_inline(described_class.new(state: true))
      expect(node.to_html).not_to include("○ auth")
    end
  end
end
