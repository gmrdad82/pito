# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Shell::MiniStatus::AuthComponent do
  before { AppSetting.where(key: AppSetting::NICKNAME_KEY).delete_all }
  after  { AppSetting.where(key: AppSetting::NICKNAME_KEY).delete_all }

  describe "default state" do
    it "defaults to unauthenticated (state: false)" do
      node = render_inline(described_class.new)
      expect(node.to_html).to include("● tarnished")
    end
  end

  describe "state: false (anonymous)" do
    it "renders the anonymous label in a red span" do
      node = render_inline(described_class.new(state: false))
      expect(node.css("span.text-red").text).to include("● tarnished")
    end

    it "does not render the authenticated shimmer span" do
      node = render_inline(described_class.new(state: false))
      expect(node.css("span.pito-me-shimmer")).to be_empty
    end
  end

  describe "state: true (authenticated)" do
    context "with default nickname (gmrdad82)" do
      it "renders the shimmering '■ gmrdad82' label (G70: the me-shimmer, green with the yellow contrast band)" do
        node = render_inline(described_class.new(state: true))
        green_span = node.css("span.pito-me-shimmer").first
        expect(green_span).to be_present
        expect(green_span.text.strip).to eq("■ gmrdad82")
      end

      it "renders the 'gmrdad82' label when authenticated" do
        node = render_inline(described_class.new(state: true))
        expect(node.to_html).to include("■ gmrdad82")
      end
    end

    context "with a custom nickname" do
      before { AppSetting.nickname = "Foo" }

      it "renders the custom nickname in the shimmer label" do
        node = render_inline(described_class.new(state: true))
        green_span = node.css("span.pito-me-shimmer").first
        expect(green_span).to be_present
        expect(green_span.text.strip).to eq("■ Foo")
      end
    end

    it "does not render the anonymous label" do
      node = render_inline(described_class.new(state: true))
      expect(node.to_html).not_to include("● tarnished")
    end
  end

  # G87: the suffix span is the bar's DEDICATED app-version slot — the cable
  # heartbeat (pito--version-watch) writes the server's version into it live.
  describe "the version slot (G87)" do
    it "the suffix span carries the stable slot id" do
      allow(Pito::Version).to receive(:suffix).and_return("1.1.1")
      node = render_inline(described_class.new(state: true))
      slot = node.css("span##{described_class::VERSION_SLOT_ID}").first
      expect(slot).to be_present
      expect(slot.text).to eq("@1.1.1")
    end
  end

  describe "version suffix (@tag in prod / @host in dev)" do
    it "appends a muted @suffix after the nickname when authenticated" do
      allow(Pito::Version).to receive(:suffix).and_return("0.8.5")
      node   = render_inline(described_class.new(state: true))
      suffix = node.css("span.text-fg-dim").first
      expect(suffix).to be_present
      expect(suffix.text).to eq("@0.8.5")
      # shimmer nickname span stays clean (suffix is its own muted span)
      expect(node.css("span.pito-me-shimmer").first.text.strip).to eq("■ gmrdad82")
    end

    it "renders no suffix when Version.suffix is nil" do
      allow(Pito::Version).to receive(:suffix).and_return(nil)
      node = render_inline(described_class.new(state: true))
      expect(node.css("span.text-fg-dim")).to be_empty
    end

    it "renders no suffix when unauthenticated (even if a version is present)" do
      allow(Pito::Version).to receive(:suffix).and_return("0.8.5")
      node = render_inline(described_class.new(state: false))
      expect(node.css("span.text-fg-dim")).to be_empty
    end
  end
end
