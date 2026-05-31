# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::ErrorComponent do
  describe "#initialize" do
    it "resolves the message via I18n" do
      comp = described_class.new(
        payload: {
          message_key: "pito.slash.errors.unknown_verb",
          message_args: { verb: "oops" }
        }
      )
      node = render_inline(comp)
      expect(node.css("span.text-fg").text).to include("oops")
    end

    it "interpolates message_args into the translation" do
      comp = described_class.new(
        payload: {
          message_key: "pito.slash.errors.parse_failed",
          message_args: { raw: "bad input" }
        }
      )
      node = render_inline(comp)
      expect(node.css("span.text-fg").text).to include("bad input")
    end

    it "handles missing message_args gracefully (defaults to empty hash)" do
      # pito.slash.errors.unknown_verb requires :verb — omitting args yields
      # a missing-interpolation fallback from I18n; we just assert it renders
      # without raising.
      expect do
        render_inline(described_class.new(
          payload: { message_key: "pito.event.thought.prefix" }
        ))
      end.not_to raise_error
    end
  end

  describe "rendered output" do
    subject(:node) do
      render_inline(described_class.new(
        payload: {
          message_key: "pito.slash.errors.unknown_verb",
          message_args: { verb: "whoops" }
        }
      ))
    end

    it "renders the error message inside span.text-fg" do
      expect(node.css("span.text-fg").text).to include("whoops")
    end

    it "renders an accent border bar (red border passed to Segment)" do
      bar = node.css("div[style*='width: 4px']").first
      expect(bar).not_to be_nil
      expect(bar["style"]).to include("var(--accent-red)")
    end

    it "renders inside the segment flex wrapper" do
      expect(node.css("div.flex").first).not_to be_nil
    end

    it "contains exactly one span.text-fg" do
      expect(node.css("span.text-fg").size).to eq(1)
    end
  end
end
