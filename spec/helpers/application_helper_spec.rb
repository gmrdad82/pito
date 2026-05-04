require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#nav_link" do
    it "returns a bracketed link when not on the current page" do
      allow(helper).to receive(:current_page?).with("/channels").and_return(false)
      result = helper.nav_link("channels", "/channels")
      expect(result).to include("<a")
      expect(result).to include("[<span")
      expect(result).to include("channels</span>")
      expect(result).to include("/channels")
      expect(result).to include("bracketed")
    end

    # Item 6 — On desktop, the full word renders inside .hide-mobile;
    # on mobile, the short label renders inside .show-mobile. Both
    # variants always live in the DOM so the toggle is pure CSS.
    it "renders both desktop full label and mobile short label spans" do
      allow(helper).to receive(:current_page?).with("/channels").and_return(false)
      result = helper.nav_link("channels", "/channels", short: "C")
      expect(result).to include('<span class="hide-mobile">channels</span>')
      expect(result).to include('<span class="show-mobile">C</span>')
    end

    it "defaults the short label to the uppercased first character of the full label" do
      allow(helper).to receive(:current_page?).with("/projects").and_return(false)
      result = helper.nav_link("projects", "/projects")
      expect(result).to include('<span class="show-mobile">P</span>')
    end

    it "returns a bracketed bold span when on the current page" do
      allow(helper).to receive(:current_page?).with("/").and_return(true)
      result = helper.nav_link("home", "/")
      expect(result).to include("bracketed-active")
      expect(result).to include("home")
      expect(result).not_to include("<a")
    end

    it "treats short: '' as desktop-only — no mobile label rendered" do
      # Used for the [home] nav link: the logo image already routes
      # home, so on mobile we omit the bracketed label entirely. The
      # helper still emits the desktop label inside .hide-mobile.
      allow(helper).to receive(:current_page?).with("/").and_return(false)
      result = helper.nav_link("home", "/", short: "")
      expect(result).to include('<span class="hide-mobile">home</span>')
      expect(result).not_to include('class="show-mobile"')
    end
  end

  describe "#breadcrumb" do
    it "renders bracketed linked segments and last segment bold" do
      helper.breadcrumb([ "channels", "/channels" ], "details")
      html = helper.content_for(:breadcrumbs)
      expect(html).to include("bracketed")
      expect(html).to include("channels")
      expect(html).to include("bracketed-active")
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

  describe "#format_video_watch_time" do
    it "returns dash for nil" do
      expect(helper.format_video_watch_time(nil)).to eq("—")
    end

    it "returns dash for zero" do
      expect(helper.format_video_watch_time(0)).to eq("—")
    end

    it "rounds sub-30-minute totals to 0h" do
      expect(helper.format_video_watch_time(15)).to eq("0h")
    end

    it "rounds 30+ minutes up to 1h" do
      expect(helper.format_video_watch_time(30)).to eq("1h")
      expect(helper.format_video_watch_time(45)).to eq("1h")
    end

    it "rounds to nearest hour (half-up)" do
      expect(helper.format_video_watch_time(89)).to eq("1h")
      expect(helper.format_video_watch_time(90)).to eq("2h")
      expect(helper.format_video_watch_time(125)).to eq("2h")
    end

    it "formats large values with comma delimiter and h suffix" do
      expect(helper.format_video_watch_time(72_060)).to eq("1,201h")
      expect(helper.format_video_watch_time(1_066_983)).to eq("17,783h")
      expect(helper.format_video_watch_time(1_066_983 + 30)).to eq("17,784h")
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
