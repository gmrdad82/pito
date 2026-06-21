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

    it "does not render the authenticated disc alone" do
      node = render_inline(described_class.new(state: false))
      expect(node.css("span.text-green")).to be_empty
    end
  end

  describe "state: true (authenticated)" do
    context "with default nickname (gmrdad82)" do
      it "renders the green '■ gmrdad82' label" do
        node = render_inline(described_class.new(state: true))
        green_span = node.css("span.text-green").first
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

      it "renders the custom nickname in the green label" do
        node = render_inline(described_class.new(state: true))
        green_span = node.css("span.text-green").first
        expect(green_span).to be_present
        expect(green_span.text.strip).to eq("■ Foo")
      end
    end

    it "does not render the anonymous label" do
      node = render_inline(described_class.new(state: true))
      expect(node.to_html).not_to include("● tarnished")
    end
  end
end
