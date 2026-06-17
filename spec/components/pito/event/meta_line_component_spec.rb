# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::MetaLineComponent do
  # The timestamp now rides inline on the first line via TimestampPrefixComponent;
  # this footer carries only handle/channel (see timestamp_prefix_component_spec).

  describe "handle" do
    it "renders the handle in purple via HandleComponent when present" do
      node = render_inline(described_class.new(handle: "alpha-42"))
      purple = node.css("span.text-purple").first
      expect(purple).not_to be_nil
      expect(purple.text).to eq("#alpha-42")
    end

    it "does not render anything when handle is nil and no channel" do
      node = render_inline(described_class.new(handle: nil))
      expect(node.css("span.text-purple")).to be_empty
    end
  end

  describe "shift+r affordance" do
    it "renders a hidden, yellow `shift+r` hint (no leading dot) when a handle is present" do
      node = render_inline(described_class.new(handle: "alpha-42"))
      hint = node.css("[data-pito-lasthashtag-hint]").first
      expect(hint).not_to be_nil
      expect(hint["class"]).to include("hidden")
      expect(hint["class"]).to include("text-yellow")
      expect(hint.text.strip).to eq("shift+r")
    end

    it "does not render the hint when there is no handle" do
      node = render_inline(described_class.new(channel: "all"))
      expect(node.css("[data-pito-lasthashtag-hint]")).to be_empty
    end
  end

  describe "separator (·)" do
    it "renders a · separator between handle and @channel when both are present" do
      node = render_inline(described_class.new(handle: "gamma-5", channel: "manfyhard"))
      separators = node.to_html.scan("·")
      expect(separators.size).to be >= 1
    end

    it "renders no separator when only a handle is present" do
      node = render_inline(described_class.new(handle: "beta-1"))
      expect(node.to_html).not_to include("·")
    end

    it "renders no separator when only a channel is present" do
      node = render_inline(described_class.new(channel: "all"))
      expect(node.to_html).not_to include("·")
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

  describe "handle and channel present" do
    subject(:node) do
      render_inline(described_class.new(handle: "delta-9", channel: "all"))
    end

    it "renders the handle in purple" do
      expect(node.css("span.text-purple").first.text).to eq("#delta-9")
    end

    it "renders @all in cyan" do
      expect(node.css("span.text-cyan").first.text).to eq("@all")
    end

    it "includes at least one separator" do
      expect(node.to_html.scan("·").size).to be >= 1
    end
  end

  describe "all nil (empty)" do
    it "renders nothing — no handle or channel spans" do
      node = render_inline(described_class.new)
      expect(node.css("span.text-purple")).to be_empty
      expect(node.css("span.text-cyan")).to be_empty
    end
  end
end
