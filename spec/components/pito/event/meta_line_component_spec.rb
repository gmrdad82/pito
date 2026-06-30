# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::MetaLineComponent do
  # The timestamp now rides inline on the first line via TimestampPrefixComponent;
  # this footer carries only handle/channel (see timestamp_prefix_component_spec).

  describe "handle" do
    it "renders the reply handle as muted text via HandleComponent when present" do
      node = render_inline(described_class.new(handle: "alpha-42"))
      hashtag = node.css("span[data-pito-handle]").first
      expect(hashtag).not_to be_nil
      expect(hashtag.text).to eq("#alpha-42")
    end

    it "does not render anything when handle is nil and no channel" do
      node = render_inline(described_class.new(handle: nil))
      expect(node.css("span[data-pito-handle]")).to be_empty
    end

    it "is decorative — #hashtag carries no chat-prefill controller or action" do
      node = render_inline(described_class.new(handle: "alpha-42"))
      hashtag = node.css("span[data-pito-handle]").first
      expect(hashtag["data-controller"]).to be_nil
      expect(hashtag["data-action"]).to be_nil
      expect(hashtag["data-pito--chat-prefill-text-value"]).to be_nil
    end
  end

  describe "shift+r affordance" do
    it "renders a hidden `shift+r` hint (keybinding shimmer, no leading dot) when a handle is present" do
      node = render_inline(described_class.new(handle: "alpha-42"))
      hint = node.css("[data-pito-lasthashtag-hint]").first
      expect(hint).not_to be_nil
      expect(hint["class"]).to include("hidden")
      expect(hint.css("span.pito-action-shimmer.text-yellow")).not_to be_empty
      expect(hint.text.strip).to eq("shift+r")
    end

    it "wires the shift+r hint to prefill `#<handle> ` instead of synthesizing a keydown" do
      node = render_inline(described_class.new(handle: "alpha-42"))
      kbd = node.css("[data-pito-lasthashtag-hint] span.pito-action-shimmer").first
      expect(kbd["data-controller"]).to eq("pito--chat-prefill")
      expect(kbd["data-action"]).to eq("click->pito--chat-prefill#fill")
      expect(kbd["data-pito--chat-prefill-text-value"]).to eq("#alpha-42 ")
      # keeps the yellow kbd styling, drops the kbd-click wiring
      expect(kbd["class"]).to include("text-yellow")
      expect(kbd["data-controller"]).not_to include("pito--kbd-click")
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
    it "renders @channel with the token shimmer via ChannelHandleComponent when channel is present" do
      node = render_inline(described_class.new(channel: "all"))
      shimmer = node.css("span.pito-token").first
      expect(shimmer).not_to be_nil
      expect(shimmer.text).to eq("@all")
    end

    it "does not render channel span when channel is nil" do
      node = render_inline(described_class.new(channel: nil))
      expect(node.css("span.pito-token")).to be_empty
    end

    it "does not render channel span when channel is omitted" do
      node = render_inline(described_class.new)
      expect(node.css("span.pito-token")).to be_empty
    end
  end

  describe "handle and channel present" do
    subject(:node) do
      render_inline(described_class.new(handle: "delta-9", channel: "all"))
    end

    it "renders the reply handle as muted text" do
      expect(node.css("span[data-pito-handle]").first.text).to eq("#delta-9")
    end

    it "renders @all with the token shimmer" do
      expect(node.css("span.pito-token").first.text).to eq("@all")
    end

    it "includes at least one separator" do
      expect(node.to_html.scan("·").size).to be >= 1
    end
  end

  describe "all nil (empty)" do
    it "renders nothing — no handle or channel spans" do
      node = render_inline(described_class.new)
      expect(node.css("span[data-pito-handle]")).to be_empty
      expect(node.css("span.pito-token")).to be_empty
    end
  end
end
