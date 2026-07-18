# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::UseWidgetComponent, type: :component do
  describe "copy-only (fill: false, the default)" do
    subject(:node) { render_inline(described_class.new(text: "copy me", aria_label: "Copy the thing")) }

    it "is a self-contained pito--clipboard widget carrying the text to copy" do
      wrap = node.at_css(".pito-copy[data-controller='pito--clipboard']")
      expect(wrap).to be_present
      expect(wrap["data-pito--clipboard-text-value"]).to eq("copy me")
    end

    it "renders the lucide copy ICON button (action-shimmer class), not the word Copy" do
      btn = node.at_css("button.pito-copy__btn[data-action='click->pito--clipboard#copy']")
      expect(btn).to be_present
      expect(btn["aria-label"]).to eq("Copy the thing")
      expect(btn.at_css("svg.pito-icon")).to be_present
      expect(btn.text).not_to include("Copy")
    end

    it "renders exactly one .pito-copy__btn (no fill button)" do
      expect(node.css(".pito-copy__btn").size).to eq(1)
      expect(node.at_css("[data-pito-use-widget-fill]")).to be_nil
    end

    it "has a separate empty Copied! feedback target" do
      fb = node.at_css(".pito-copy__feedback[data-pito--clipboard-target='feedback']")
      expect(fb).to be_present
      expect(fb.text.strip).to eq("")
    end
  end

  describe "fill: true" do
    subject(:node) do
      render_inline(described_class.new(text: "list games", aria_label: "Copy command", fill: true))
    end

    it "still renders the copy button unchanged" do
      btn = node.at_css("button.pito-copy__btn[data-action='click->pito--clipboard#copy']")
      expect(btn).to be_present
      expect(btn["aria-label"]).to eq("Copy command")
    end

    it "renders a second stage-in-chatbox button wired to pito--chat-prefill" do
      fill_btn = node.at_css("button[data-pito-use-widget-fill]")
      expect(fill_btn).to be_present
      expect(fill_btn["class"]).to eq("pito-copy__btn pito-copy__fill")
      expect(fill_btn["data-controller"]).to eq("pito--chat-prefill")
      expect(fill_btn["data-pito--chat-prefill-text-value"]).to eq("list games")
      expect(fill_btn.at_css("svg.pito-icon")).to be_present
    end

    it "does NOT carry a submit value on the fill button (stage-only, never submits)" do
      fill_btn = node.at_css("button[data-pito-use-widget-fill]")
      expect(fill_btn["data-pito--chat-prefill-submit-value"]).to be_nil
    end

    it "stacks BOTH controllers' click actions on the fill button (copy + fill)" do
      fill_btn = node.at_css("button[data-pito-use-widget-fill]")
      expect(fill_btn["data-action"]).to eq("click->pito--clipboard#copy click->pito--chat-prefill#fill")
    end

    it "defaults the fill button's aria-label to the stage hint" do
      fill_btn = node.at_css("button[data-pito-use-widget-fill]")
      expect(fill_btn["aria-label"]).to eq("Stage command in chatbox")
    end

    it "accepts a custom fill_aria_label" do
      node = render_inline(described_class.new(text: "x", aria_label: "Copy", fill: true, fill_aria_label: "Custom label"))
      expect(node.at_css("button[data-pito-use-widget-fill]")["aria-label"]).to eq("Custom label")
    end

    it "renders exactly two .pito-copy__btn buttons" do
      expect(node.css(".pito-copy__btn").size).to eq(2)
    end

    it "keeps the Copied! feedback span as the LAST child" do
      wrap = node.at_css(".pito-copy")
      expect(wrap.children.last["data-pito--clipboard-target"]).to eq("feedback")
    end

    it "root span still carries the pito--clipboard controller and the same text value" do
      wrap = node.at_css(".pito-copy[data-controller='pito--clipboard']")
      expect(wrap).to be_present
      expect(wrap["data-pito--clipboard-text-value"]).to eq("list games")
    end
  end
end
