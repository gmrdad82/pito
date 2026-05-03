require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#nav_link" do
    it "returns a bracketed link when not on the current page" do
      allow(helper).to receive(:current_page?).with("/channels").and_return(false)
      result = helper.nav_link("channels", "/channels")
      expect(result).to include("<a")
      expect(result).to include("[<span")
      expect(result).to include("channels</span>]")
      expect(result).to include("channels")
      expect(result).to include("/channels")
      expect(result).to include("bracketed")
    end

    it "returns a bracketed bold span when on the current page" do
      allow(helper).to receive(:current_page?).with("/").and_return(true)
      result = helper.nav_link("home", "/")
      expect(result).to include("<span")
      expect(result).to include("[home]")
      expect(result).to include("font-weight: bold")
      expect(result).not_to include("<a")
    end
  end

  describe "#breadcrumb" do
    it "renders bracketed linked segments and last segment bold" do
      helper.breadcrumb([ "channels", "/channels" ], "details")
      html = helper.content_for(:breadcrumbs)
      expect(html).to include("bracketed")
      expect(html).to include("channels")
      expect(html).to include("font-weight: bold")
      expect(html).to include("details")
    end

    it "uses / separator" do
      helper.breadcrumb([ "a", "/a" ], "b")
      html = helper.content_for(:breadcrumbs)
      expect(html).to include(" / ")
    end

    it "truncates long non-last labels to 32 chars" do
      long_label = "A" * 50
      helper.breadcrumb([ long_label, "/somewhere" ], "last")
      html = helper.content_for(:breadcrumbs)
      expect(html).to include("A" * 31 + "…")
    end

    it "renders nothing when not called" do
      expect(helper.content_for?(:breadcrumbs)).to be false
    end
  end

  describe "#format_watch_time" do
    it "returns dash for nil" do
      expect(helper.format_watch_time(nil)).to eq("—")
    end

    it "returns dash for zero" do
      expect(helper.format_watch_time(0)).to eq("—")
    end

    it "formats minutes only when under an hour" do
      expect(helper.format_watch_time(45)).to eq("45m")
    end

    it "formats hours and minutes" do
      expect(helper.format_watch_time(125)).to eq("2h 5m")
    end

    it "formats large values with delimiter" do
      expect(helper.format_watch_time(72_060)).to eq("1,201h 0m")
    end
  end

  describe "#pane_breadcrumb_label" do
    let(:video1) { build_stubbed(:video, title: "alpha", channel: build_stubbed(:channel)) }
    let(:video2) { build_stubbed(:video, title: "beta", channel: build_stubbed(:channel)) }

    it "returns full title for single video pane" do
      expect(helper.pane_breadcrumb_label([ video1 ])).to eq("alpha")
    end

    it "joins multiple panes with dot separator" do
      result = helper.pane_breadcrumb_label([ video1, video2 ])
      expect(result).to include("alpha")
      expect(result).to include("·")
      expect(result).to include("beta")
    end

    it "truncates long names with ellipsis" do
      long = build_stubbed(:video, title: "a very long video name here", channel: build_stubbed(:channel))
      result = helper.pane_breadcrumb_label([ long, video2 ])
      expect(result).to include("…")
    end

    it "shows +N more for excess panes" do
      videos = 5.times.map { |i| build_stubbed(:video, title: "v#{i}", channel: build_stubbed(:channel)) }
      result = helper.pane_breadcrumb_label(videos)
      expect(result).to include("+2 more")
    end

    it "falls back to id-only label for channels (no title column)" do
      channel = build_stubbed(:channel)
      expect(helper.pane_breadcrumb_label([ channel ])).to eq("##{channel.id}")
    end
  end
end
