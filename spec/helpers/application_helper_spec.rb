require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  describe "#nav_link" do
    it "returns a link when not on the current page" do
      allow(helper).to receive(:current_page?).with("/channels").and_return(false)
      result = helper.nav_link("Channels", "/channels")
      expect(result).to include("<a")
      expect(result).to include("Channels")
      expect(result).to include("/channels")
    end

    it "returns a span when on the current page" do
      allow(helper).to receive(:current_page?).with("/").and_return(true)
      result = helper.nav_link("Dashboard", "/")
      expect(result).to include("<span")
      expect(result).to include("Dashboard")
      expect(result).not_to include("<a")
    end
  end

  describe "#breadcrumb" do
    it "renders linked segments and last segment bold, wrapped in [ ]" do
      helper.breadcrumb([ "Channels", "/channels" ], "Details")
      html = helper.content_for(:breadcrumbs)
      expect(html).to include('<a href="/channels">Channels</a>')
      expect(html).to include("font-weight: bold")
      expect(html).to start_with("[ ")
      expect(html).to end_with(" ]")
    end

    it "uses / separator" do
      helper.breadcrumb([ "A", "/a" ], "B")
      html = helper.content_for(:breadcrumbs)
      expect(html).to include(" / ")
    end

    it "truncates long labels to 32 chars" do
      long_label = "A" * 50
      helper.breadcrumb(long_label)
      html = helper.content_for(:breadcrumbs)
      expect(html).to include("A" * 29 + "...")
    end

    it "renders nothing when not called" do
      expect(helper.content_for?(:breadcrumbs)).to be false
    end
  end
end
