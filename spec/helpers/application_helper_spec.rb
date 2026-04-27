require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#nav_link" do
    it "returns a bracketed link when not on the current page" do
      allow(helper).to receive(:current_page?).with("/channels").and_return(false)
      result = helper.nav_link("channels", "/channels")
      expect(result).to include("<a")
      expect(result).to include("[ ")
      expect(result).to include("channels")
      expect(result).to include("/channels")
      expect(result).to include("bracketed")
    end

    it "returns a bracketed bold span when on the current page" do
      allow(helper).to receive(:current_page?).with("/").and_return(true)
      result = helper.nav_link("home", "/")
      expect(result).to include("<span")
      expect(result).to include("[ home ]")
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
      expect(html).to include("A" * 29 + "...")
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
    it "returns full title for single pane" do
      channel = build(:channel, title: "my channel")
      expect(helper.pane_breadcrumb_label([ channel ])).to eq("my channel")
    end

    it "joins multiple panes with dot separator" do
      channels = [ build(:channel, title: "alpha"), build(:channel, title: "beta") ]
      result = helper.pane_breadcrumb_label(channels)
      expect(result).to include("alpha")
      expect(result).to include("·")
      expect(result).to include("beta")
    end

    it "truncates long names with ellipsis" do
      channel = build(:channel, title: "a very long channel name here")
      channels = [ channel, build(:channel, title: "other") ]
      result = helper.pane_breadcrumb_label(channels)
      expect(result).to include("…")
    end

    it "shows +N more for excess panes" do
      channels = 5.times.map { |i| build(:channel, title: "ch#{i}") }
      result = helper.pane_breadcrumb_label(channels)
      expect(result).to include("+2 more")
    end
  end
end
