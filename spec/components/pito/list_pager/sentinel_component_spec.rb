# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::ListPager::SentinelComponent do
  describe "with a next_url (more pages remain)" do
    subject(:node) { render_inline(described_class.new(next_url: "/notifications?after=abc123")) }

    it "renders the sentinel element with the stable id" do
      expect(node.css("##{described_class::SENTINEL_ID}")).not_to be_empty
    end

    it "carries the opaque next-page URL for the pager to fetch" do
      el = node.css("##{described_class::SENTINEL_ID}").first
      expect(el["data-pager-next-url"]).to eq("/notifications?after=abc123")
    end

    it "registers as the pager's sentinel target" do
      el = node.css("##{described_class::SENTINEL_ID}").first
      expect(el["data-pito--list-pager-target"]).to eq("sentinel")
    end

    it "renders a hidden shimmer loader target" do
      loader = node.css('[data-pito--list-pager-target="loader"]').first
      expect(loader).to be_present
      expect(loader["class"]).to include("hidden")
      expect(loader.css("span.pito-network-shimmer")).not_to be_empty
    end

    it "does NOT render the end-of-list copy" do
      expect(node.text).not_to include(Pito::Copy.render("pito.copy.list_end"))
    end
  end

  describe "without a next_url (end of list)" do
    subject(:node) { render_inline(described_class.new(next_url: nil)) }

    it "still renders the sentinel element (so the append can target it)" do
      expect(node.css("##{described_class::SENTINEL_ID}")).not_to be_empty
    end

    it "carries no next-page URL (the pager stops)" do
      el = node.css("##{described_class::SENTINEL_ID}").first
      expect(el["data-pager-next-url"]).to be_nil
    end

    it "renders a generic end-of-list message from pito.copy.list_end" do
      variants = I18n.t("pito.copy.list_end")
      expect(variants).to include(node.css("p").text.strip)
    end

    it "renders no shimmer loader" do
      expect(node.css('[data-pito--list-pager-target="loader"]')).to be_empty
    end
  end

  it "treats a blank next_url as the end state" do
    node = render_inline(described_class.new(next_url: ""))
    el = node.css("##{described_class::SENTINEL_ID}").first
    expect(el["data-pager-next-url"]).to be_nil
  end
end
