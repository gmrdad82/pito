# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Channel::VisitComponent do
  def build_channel(attrs = {})
    build_stubbed(:channel, {
      id:                 42,
      title:              "Test Channel",
      handle:             "@testhandle",
      youtube_channel_id: "UCtest123",
      avatar_url:         nil
    }.merge(attrs))
  end

  describe "shimmer copy" do
    it "renders the pito-shimmer span" do
      channel = build_channel(handle: "@testhandle")
      html = render_inline(described_class.new(channel:)).to_html
      expect(html).to include("pito-shimmer")
    end

    it "interpolates the @handle in the copy text" do
      channel = build_channel(handle: "@testhandle")
      html = render_inline(described_class.new(channel:)).to_html
      expect(html).to include("@testhandle")
    end
  end

  describe "youtube link" do
    it "renders a link to the @handle YouTube URL when handle is present" do
      channel = build_channel(handle: "@testhandle")
      html = render_inline(described_class.new(channel:)).to_html
      expect(html).to include("https://www.youtube.com/@testhandle")
    end

    it "renders a /channel/ URL when handle is blank" do
      channel = build_channel(handle: nil, youtube_channel_id: "UCabc")
      html = render_inline(described_class.new(channel:)).to_html
      expect(html).to include("https://www.youtube.com/channel/UCabc")
    end

    it "opens in a new tab (target=_blank)" do
      channel = build_channel(handle: "@testhandle")
      node = render_inline(described_class.new(channel:))
      link = node.css("a[href*='youtube.com']").first
      expect(link["target"]).to eq("_blank")
    end

    it "has rel=noopener" do
      channel = build_channel(handle: "@testhandle")
      node = render_inline(described_class.new(channel:))
      link = node.css("a[href*='youtube.com']").first
      expect(link["rel"]).to include("noopener")
    end

    it "renders the anchor with the hidden class" do
      channel = build_channel(handle: "@testhandle")
      node = render_inline(described_class.new(channel:))
      link = node.css("a[href*='youtube.com']").first
      expect(link["class"]).to include("hidden")
    end
  end

  describe "Stimulus controller data attributes" do
    it "sets data-controller=pito--auto-visit on the wrapper" do
      channel = build_channel
      node = render_inline(described_class.new(channel:))
      wrapper = node.css("[data-controller='pito--auto-visit']").first
      expect(wrapper).not_to be_nil
    end

    it "sets delay value to 1000" do
      channel = build_channel
      node = render_inline(described_class.new(channel:))
      wrapper = node.css("[data-controller='pito--auto-visit']").first
      expect(wrapper["data-pito--auto-visit-delay-value"]).to eq("1000")
    end

    it "sets link-id-value on the wrapper" do
      channel = build_channel
      node = render_inline(described_class.new(channel:))
      wrapper = node.css("[data-controller='pito--auto-visit']").first
      expect(wrapper["data-pito--auto-visit-link-id-value"]).to be_present
    end

    it "hidden anchor id matches link-id-value" do
      channel = build_channel
      node = render_inline(described_class.new(channel:))
      wrapper = node.css("[data-controller='pito--auto-visit']").first
      link_id = wrapper["data-pito--auto-visit-link-id-value"]
      anchor = node.css("##{link_id}").first
      expect(anchor).not_to be_nil
    end

    it "sets the consume-url-value so the controller can persist consumption" do
      channel = build_channel
      node = render_inline(described_class.new(channel:))
      wrapper = node.css("[data-controller='pito--auto-visit']").first
      expect(wrapper["data-pito--auto-visit-consume-url-value"]).to be_present
    end
  end

  describe "visited (consumed) state" do
    it "does NOT mount the auto-visit controller (no auto-click on refresh)" do
      channel = build_channel
      node = render_inline(described_class.new(channel:, state: :visited))
      expect(node.css("[data-controller='pito--auto-visit']")).to be_empty
    end

    it "renders no shimmer" do
      channel = build_channel
      html = render_inline(described_class.new(channel:, state: :visited)).to_html
      expect(html).not_to include("pito-shimmer")
    end

    it "renders a visible manual [view] link to the YouTube page" do
      channel = build_channel(handle: "@testhandle")
      node = render_inline(described_class.new(channel:, state: :visited))
      link = node.css("a[href*='youtube.com']").first
      expect(link).not_to be_nil
      expect(link.text).to include("[view]")
      expect(link["target"]).to eq("_blank")
      expect(link["class"]).not_to include("hidden")
    end
  end
end
