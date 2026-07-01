# frozen_string_literal: true

require "rails_helper"

# Pito::Shell::ScrollNavComponent renders two pill <template>s (top + bottom).
# The pito--scroll-nav Stimulus controller CREATES a pill (a clone of the
# matching template) and appends it when needed, and REMOVES it from the DOM
# when not — never show/hide. The component provides the templates, copy, and the
# count-variants JSON.
RSpec.describe Pito::Shell::ScrollNavComponent do
  subject(:node) { render_inline(described_class.new) }

  # ── Two pill templates, nothing live by default ─────────────────────────────

  it "renders exactly 2 pill templates (top + bottom)" do
    expect(node.css("[data-pito--scroll-nav-target='topTemplate'], [data-pito--scroll-nav-target='bottomTemplate']").length).to eq(2)
    expect(node.css(".pito-scroll-nav__pill--top").length).to eq(1)
    expect(node.css(".pito-scroll-nav__pill--bottom").length).to eq(1)
  end

  it "renders NO `hidden` class on the pills (create/remove, not show/hide)" do
    node.css(".pito-scroll-nav__pill").each do |pill|
      expect(pill["class"]).not_to include("hidden")
    end
  end

  it "renders no pill with a visible class by default" do
    expect(node.css(".pito-scroll-nav__pill--visible")).to be_empty
  end

  # ── Yellow clickable tokens ──────────────────────────────────────────────────

  it "renders the top pill yellow token with jumpTop action" do
    token = node.css("[data-action='click->pito--scroll-nav#jumpTop']")
    expect(token).not_to be_empty
    expect(token.first["class"]).to include("pito-action-shimmer")
  end

  it "renders the bottom pill yellow token with jumpBottom action" do
    token = node.css("[data-action='click->pito--scroll-nav#jumpBottom']")
    expect(token).not_to be_empty
    expect(token.first["class"]).to include("pito-action-shimmer")
  end

  it "labels the top token ctrl+home" do
    token = node.css("[data-action='click->pito--scroll-nav#jumpTop']")
    expect(token.text).to eq("ctrl+home")
  end

  it "labels the bottom token ctrl+end" do
    token = node.css("[data-action='click->pito--scroll-nav#jumpBottom']")
    expect(token.text).to eq("ctrl+end")
  end

  # ── Jump copy (1-variant, server-rendered) ───────────────────────────────────

  it "includes the compact jump-to-start arrow copy in the top pill" do
    top_pill = node.css(".pito-scroll-nav__pill--top").first
    expect(top_pill.text).to include("[<-")
  end

  it "includes the compact jump-to-end arrow copy in the bottom pill" do
    bottom_pill = node.css(".pito-scroll-nav__pill--bottom").first
    expect(bottom_pill.text).to include("jump ->]")
  end

  # ── Count spans (JS-filled, empty on render) ─────────────────────────────────

  it "renders a count span in each pill (empty — filled by JS)" do
    counts = node.css(".pito-scroll-nav__pill [data-scroll-nav-count]")
    expect(counts.length).to eq(2)
    counts.each { |c| expect(c.text.strip).to eq("") }
  end

  # ── 50-variant JSON catalog ──────────────────────────────────────────────────

  it "emits the count variants JSON on the controller root element" do
    root = node.css("[data-pito--scroll-nav-variants-value]").first
    expect(root).not_to be_nil
  end

  it "emits exactly 50 count variants" do
    root     = node.css("[data-pito--scroll-nav-variants-value]").first
    variants = JSON.parse(root["data-pito--scroll-nav-variants-value"])
    expect(variants.length).to eq(50)
  end

  it "every count variant contains %{count} and %{direction} placeholders" do
    root     = node.css("[data-pito--scroll-nav-variants-value]").first
    variants = JSON.parse(root["data-pito--scroll-nav-variants-value"])
    variants.each do |tmpl|
      expect(tmpl).to include("%{count}"),    "template #{tmpl.inspect} missing %{count}"
      expect(tmpl).to include("%{direction}"), "template #{tmpl.inspect} missing %{direction}"
    end
  end

  # ── Stimulus controller wired on the root ───────────────────────────────────

  it "declares the pito--scroll-nav controller on the wrapper" do
    root = node.css("[data-controller~='pito--scroll-nav']").first
    expect(root).not_to be_nil
  end

  # ── Design rules ─────────────────────────────────────────────────────────────

  it "uses no text-size utilities (monospace one-size design rule)" do
    SIZE_RE = /\btext-(xs|sm|base|lg|xl|2xl|3xl)\b/
    has_sized = node.css("*").any? { |el| SIZE_RE.match?(el["class"].to_s) }
    expect(has_sized).to be(false)
  end

  it "uses no inline style= attributes (design rule: no inline style)" do
    styled = node.css("[style]")
    expect(styled).to be_empty
  end
end
