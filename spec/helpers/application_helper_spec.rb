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
