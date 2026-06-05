# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Palette::CtrlK::CommandComponent do
  let(:label_key) { "pito.palette.ctrl_k.commands.connect" }
  let(:insert)    { "/connect" }

  subject(:node) { render_inline(described_class.new(label_key:, insert:)) }

  describe "wrapper element" do
    it "has the correct Stimulus item target" do
      expect(node.css("[data-pito--command-palette-target='item']")).not_to be_empty
    end

    it "sets data-insert to the insert string" do
      item = node.css("[data-pito--command-palette-target='item']").first
      expect(item["data-insert"]).to eq(insert)
    end

    it "sets data-label to the downcased combination of label and insert" do
      item = node.css("[data-pito--command-palette-target='item']").first
      label = I18n.t(label_key)
      expected = "#{label} #{insert}".downcase
      expect(item["data-label"]).to eq(expected)
    end

    it "data-label is fully lowercase" do
      item = node.css("[data-pito--command-palette-target='item']").first
      expect(item["data-label"]).to eq(item["data-label"].downcase)
    end
  end

  describe "label span" do
    it "renders a span.text-fg containing the translated label" do
      span = node.css("span.text-fg").first
      expect(span).not_to be_nil
      expect(span.text.strip).to eq(I18n.t(label_key))
    end
  end

  describe "insert span" do
    it "renders a span.text-fg-dim containing the insert text" do
      span = node.css("span.text-fg-dim").first
      expect(span).not_to be_nil
      expect(span.text.strip).to eq(insert)
    end
  end

  describe "with a different real i18n key" do
    let(:label_key) { "pito.palette.ctrl_k.commands.disconnect" }
    let(:insert)    { "/disconnect <@handle>" }

    it "renders the disconnect label" do
      expect(node.css("span.text-fg").first.text.strip).to eq(I18n.t(label_key))
    end

    it "renders the disconnect insert text" do
      expect(node.css("span.text-fg-dim").first.text.strip).to eq(insert)
    end

    it "builds data-label from the disconnect label and insert" do
      item = node.css("[data-pito--command-palette-target='item']").first
      expected = "#{I18n.t(label_key)} #{insert}".downcase
      expect(item["data-label"]).to eq(expected)
    end
  end
end
