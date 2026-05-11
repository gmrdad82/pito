require "rails_helper"

RSpec.describe "channels/_links.html.erb", type: :view do
  let(:channel) { build_stubbed(:channel) }

  context "when links is nil" do
    before { channel.links = nil }

    it "renders the muted empty-state caption" do
      render "channels/links", channel: channel
      expect(rendered).to include("no links yet.")
      expect(rendered).to include('class="caption"')
    end
  end

  context "when links is the empty array" do
    before { channel.links = [] }

    it "renders the muted empty-state caption" do
      render "channels/links", channel: channel
      expect(rendered).to include("no links yet.")
    end
  end

  context "when links contains a single entry" do
    before do
      channel.links = [ { "title" => "GitHub", "url" => "https://github.com/example" } ]
    end

    it "renders the entry as a bracketed link" do
      render "channels/links", channel: channel
      expect(rendered).to include("GitHub")
      expect(rendered).to include('href="https://github.com/example"')
    end

    it "opens the link in a new tab with rel=noopener noreferrer" do
      render "channels/links", channel: channel
      expect(rendered).to include('target="_blank"')
      expect(rendered).to include('rel="noopener noreferrer"')
    end

    it "does not render the empty-state caption" do
      render "channels/links", channel: channel
      expect(rendered).not_to include("no links yet.")
    end
  end

  context "when links contains five entries (the max)" do
    before do
      channel.links = (1..5).map { |n| { "title" => "Link #{n}", "url" => "https://example.test/#{n}" } }
    end

    it "renders every entry" do
      render "channels/links", channel: channel
      (1..5).each do |n|
        expect(rendered).to include("Link #{n}")
        expect(rendered).to include("https://example.test/#{n}")
      end
    end
  end

  context "when links has malformed entries (defense in depth)" do
    before do
      channel.links = [
        { "title" => "Good", "url" => "https://good.example" },
        "not-a-hash",
        { "title" => "", "url" => "https://no-title.example" },
        { "title" => "No URL", "url" => "" }
      ]
    end

    it "renders the good entry without crashing" do
      expect { render "channels/links", channel: channel }.not_to raise_error
      expect(rendered).to include("Good")
      expect(rendered).to include("https://good.example")
    end

    it "skips the non-Hash entry" do
      render "channels/links", channel: channel
      expect(rendered).not_to include("not-a-hash")
    end

    it "skips entries with blank title or URL" do
      render "channels/links", channel: channel
      expect(rendered).not_to include("https://no-title.example")
      expect(rendered).not_to include(">No URL<")
    end
  end

  context "with symbol-keyed hash entries (defense — model always stores string keys but be lenient)" do
    before do
      channel.links = [ { title: "Symboled", url: "https://sym.example" } ]
    end

    it "renders the symbol-keyed entry" do
      render "channels/links", channel: channel
      expect(rendered).to include("Symboled")
      expect(rendered).to include("https://sym.example")
    end
  end
end
