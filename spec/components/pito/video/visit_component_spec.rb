# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Video::VisitComponent do
  def build_video(attrs = {})
    build_stubbed(:video, {
      id:                 42,
      title:              "Test Video",
      youtube_video_id:   "abc123"
    }.merge(attrs))
  end

  describe "shimmer copy" do
    it "renders the pito-network-shimmer span" do
      video = build_video(title: "My Vid")
      html = render_inline(described_class.new(video:)).to_html
      expect(html).to include("pito-network-shimmer")
    end

    it "interpolates the title in the copy text" do
      video = build_video(title: "My Vid")
      html = render_inline(described_class.new(video:)).to_html
      expect(html).to include("My Vid")
    end
  end

  describe "youtube link" do
    it "renders a link to the watch-page YouTube URL" do
      video = build_video(youtube_video_id: "abc123")
      html = render_inline(described_class.new(video:)).to_html
      expect(html).to include("https://www.youtube.com/watch?v=abc123")
    end

    it "opens in a new tab (target=_blank)" do
      video = build_video(youtube_video_id: "abc123")
      node = render_inline(described_class.new(video:))
      link = node.css("a[href*='youtube.com']").first
      expect(link["target"]).to eq("_blank")
    end

    it "has rel=noopener" do
      video = build_video(youtube_video_id: "abc123")
      node = render_inline(described_class.new(video:))
      link = node.css("a[href*='youtube.com']").first
      expect(link["rel"]).to include("noopener")
    end

    it "renders the anchor with the hidden class" do
      video = build_video(youtube_video_id: "abc123")
      node = render_inline(described_class.new(video:))
      link = node.css("a[href*='youtube.com']").first
      expect(link["class"]).to include("hidden")
    end
  end

  describe "Stimulus controller data attributes" do
    it "sets data-controller=pito--auto-visit on the wrapper" do
      video = build_video
      node = render_inline(described_class.new(video:))
      wrapper = node.css("[data-controller='pito--auto-visit']").first
      expect(wrapper).not_to be_nil
    end

    it "sets delay value to 1000" do
      video = build_video
      node = render_inline(described_class.new(video:))
      wrapper = node.css("[data-controller='pito--auto-visit']").first
      expect(wrapper["data-pito--auto-visit-delay-value"]).to eq("1000")
    end

    it "sets link-id-value on the wrapper" do
      video = build_video
      node = render_inline(described_class.new(video:))
      wrapper = node.css("[data-controller='pito--auto-visit']").first
      expect(wrapper["data-pito--auto-visit-link-id-value"]).to be_present
    end

    it "hidden anchor id matches link-id-value" do
      video = build_video
      node = render_inline(described_class.new(video:))
      wrapper = node.css("[data-controller='pito--auto-visit']").first
      link_id = wrapper["data-pito--auto-visit-link-id-value"]
      anchor = node.css("##{link_id}").first
      expect(anchor).not_to be_nil
    end

    it "sets the consume-url-value so the controller can persist consumption" do
      video = build_video
      node = render_inline(described_class.new(video:))
      wrapper = node.css("[data-controller='pito--auto-visit']").first
      expect(wrapper["data-pito--auto-visit-consume-url-value"]).to be_present
    end
  end

  describe "visited (consumed) state" do
    it "does NOT mount the auto-visit controller (no auto-click on refresh)" do
      video = build_video
      node = render_inline(described_class.new(video:, state: :visited))
      expect(node.css("[data-controller='pito--auto-visit']")).to be_empty
    end

    it "renders no shimmer" do
      video = build_video
      html = render_inline(described_class.new(video:, state: :visited)).to_html
      expect(html).not_to include("pito-network-shimmer")
    end

    it "renders a visible manual [view] link to the YouTube page" do
      video = build_video(youtube_video_id: "abc123")
      node = render_inline(described_class.new(video:, state: :visited))
      link = node.css("a[href*='youtube.com']").first
      expect(link).not_to be_nil
      expect(link.text).to include("[view]")
      expect(link["target"]).to eq("_blank")
      expect(link["class"]).not_to include("hidden")
    end
  end

  describe "destination: :youtube (default)" do
    it "uses the video's watch-page URL (www.youtube.com/watch?v=)" do
      video = build_video(youtube_video_id: "abc123")
      html = render_inline(described_class.new(video:)).to_html
      expect(html).to include("https://www.youtube.com/watch?v=abc123")
      expect(html).not_to include("studio.youtube.com")
    end

    it "also uses the watch-page URL in the :visited [view] link" do
      video = build_video(youtube_video_id: "abc123")
      html = render_inline(described_class.new(video:, state: :visited)).to_html
      expect(html).to include("https://www.youtube.com/watch?v=abc123")
    end
  end

  describe "destination: :studio" do
    it "uses the Studio URL (studio.youtube.com) in the :visiting anchor" do
      video = build_video(youtube_video_id: "abc123")
      html = render_inline(described_class.new(video:, destination: :studio)).to_html
      expect(html).to include("https://studio.youtube.com/video/abc123/edit")
      expect(html).not_to include("www.youtube.com/watch")
    end

    it "uses the Studio URL in the :visited [view] link" do
      video = build_video(youtube_video_id: "abc123")
      html = render_inline(described_class.new(video:, state: :visited, destination: :studio)).to_html
      expect(html).to include("https://studio.youtube.com/video/abc123/edit")
    end

    it "does NOT mount the auto-visit controller in the visited state" do
      video = build_video
      node = render_inline(described_class.new(video:, state: :visited, destination: :studio))
      expect(node.css("[data-controller='pito--auto-visit']")).to be_empty
    end
  end
end
