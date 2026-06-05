# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::MetaLineComponent do
  describe "timestamp" do
    it "renders a formatted time span when timestamp is present" do
      ts = Time.zone.parse("2026-06-01 19:58:00")
      node = render_inline(described_class.new(timestamp: ts))
      expect(node.css("span.text-fg-faded").map(&:text)).to include("7:58 PM")
    end

    it "does not render a timestamp span when timestamp is nil" do
      node = render_inline(described_class.new(timestamp: nil))
      expect(node.css("span.text-fg-faded").map(&:text)).not_to include(match(/\d+:\d+/))
    end

    it "formats single-digit hours without leading zero" do
      ts = Time.zone.parse("2026-06-01 09:05:00")
      node = render_inline(described_class.new(timestamp: ts))
      expect(node.css("span.text-fg-faded").map(&:text)).to include("9:05 AM")
    end
  end

  describe "handle" do
    it "renders the handle in purple via HandleComponent when present" do
      node = render_inline(described_class.new(handle: "alpha-42"))
      purple = node.css("span.text-purple").first
      expect(purple).not_to be_nil
      expect(purple.text).to eq("#alpha-42")
    end

    it "does not render a handle span when handle is nil" do
      node = render_inline(described_class.new(handle: nil))
      expect(node.css("span.text-purple")).to be_empty
    end
  end

  describe "separator (·)" do
    it "renders a · separator before the handle when timestamp is also present" do
      ts = Time.zone.parse("2026-06-01 19:58:00")
      node = render_inline(described_class.new(timestamp: ts, handle: "beta-1"))
      expect(node.to_html).to include("·")
    end

    it "renders a · separator before @channel when timestamp is also present" do
      ts = Time.zone.parse("2026-06-01 19:58:00")
      node = render_inline(described_class.new(timestamp: ts, channel: "all"))
      expect(node.to_html).to include("·")
    end

    it "renders a · separator between handle and @channel when both are present" do
      node = render_inline(described_class.new(handle: "gamma-5", channel: "manfyhard"))
      separators = node.to_html.scan("·")
      expect(separators.size).to be >= 1
    end
  end

  describe "channel" do
    it "renders @channel in cyan via ChannelHandleComponent when channel is present" do
      node = render_inline(described_class.new(channel: "all"))
      cyan = node.css("span.text-cyan").first
      expect(cyan).not_to be_nil
      expect(cyan.text).to eq("@all")
    end

    it "does not render channel span when channel is nil" do
      node = render_inline(described_class.new(channel: nil))
      expect(node.css("span.text-cyan")).to be_empty
    end

    it "does not render channel span when channel is omitted" do
      node = render_inline(described_class.new)
      expect(node.css("span.text-cyan")).to be_empty
    end
  end

  describe "all three present" do
    subject(:node) do
      ts = Time.zone.parse("2026-06-01 14:30:00")
      render_inline(described_class.new(timestamp: ts, handle: "delta-9", channel: "all"))
    end

    it "renders the formatted timestamp" do
      expect(node.css("span.text-fg-faded").map(&:text)).to include("2:30 PM")
    end

    it "renders the handle in purple" do
      expect(node.css("span.text-purple").first.text).to eq("#delta-9")
    end

    it "renders @all in cyan" do
      expect(node.css("span.text-cyan").first.text).to eq("@all")
    end

    it "includes at least two separators" do
      expect(node.to_html.scan("·").size).to be >= 2
    end
  end

  describe "all nil (empty)" do
    it "renders nothing meaningful — no timestamp, handle, or channel spans" do
      node = render_inline(described_class.new)
      expect(node.css("span.text-fg-faded")).to be_empty
      expect(node.css("span.text-purple")).to be_empty
      expect(node.css("span.text-cyan")).to be_empty
    end
  end
end
