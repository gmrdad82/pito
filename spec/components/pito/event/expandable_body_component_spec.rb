# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Event::ExpandableBodyComponent do
  describe "typewriter: param" do
    context "when typewriter: true and plain-text body" do
      it "adds data-controller~='pito--typewriter' to the plain body span" do
        node = render_inline(described_class.new(body: "Typewriter text", typewriter: true))
        span = node.css("span.text-fg[data-controller~='pito--typewriter']").first
        expect(span).not_to be_nil
        expect(span.text).to include("Typewriter text")
      end

      it "adds data-pito--typewriter-target='body' to the plain body span" do
        node = render_inline(described_class.new(body: "Typewriter text", typewriter: true))
        expect(node.css("[data-pito--typewriter-target='body']")).not_to be_empty
      end

      it "adds typewriter controller inside the expand wrapper when expandable" do
        node = render_inline(described_class.new(
          body: "Expand text",
          expand_detail: [ "detail line" ],
          expand_label: "Show",
          collapse_label: "Hide",
          typewriter: true
        ))
        expect(node.css("[data-controller~='pito--typewriter']")).not_to be_empty
      end
    end

    context "when typewriter: true but html: true" do
      it "does NOT add typewriter controller (html bodies are not animated)" do
        node = render_inline(described_class.new(body: "<b>bold</b>", html: true, typewriter: true))
        expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
      end
    end

    context "when typewriter: false (default)" do
      it "does NOT add typewriter controller" do
        node = render_inline(described_class.new(body: "Plain text"))
        expect(node.css("[data-controller~='pito--typewriter']")).to be_empty
      end
    end
  end

  describe "#expandable?" do
    it "returns false when expand_detail is empty" do
      comp = described_class.new(body: "Hello", expand_detail: [])
      expect(comp.expandable?).to be false
    end

    it "returns true when expand_detail has entries" do
      comp = described_class.new(body: "Hello", expand_detail: [ "Line one" ])
      expect(comp.expandable?).to be true
    end
  end

  describe "plain body (not expandable)" do
    it "renders span.text-fg with body text" do
      node = render_inline(described_class.new(body: "Some plain body"))
      expect(node.css("span.text-fg").first&.text).to include("Some plain body")
    end

    it "does not render the pito--expand controller" do
      node = render_inline(described_class.new(body: "Hello"))
      expect(node.css("[data-controller='pito--expand']")).to be_empty
    end
  end

  describe "nil body with no expand_detail" do
    it "renders nothing significant (no text-fg span, no expand controller)" do
      node = render_inline(described_class.new(body: nil))
      expect(node.css("span.text-fg")).to be_empty
      expect(node.css("[data-controller='pito--expand']")).to be_empty
    end
  end

  describe "expandable (expand_detail present)" do
    let(:expand_detail) { [ "3 items will be removed", "  Item A: 2", "  Item B: 1" ] }
    let(:expand_lines)  { [ "Summary line one" ] }

    subject(:node) do
      render_inline(described_class.new(
        body: "Main body text",
        expand_lines: expand_lines,
        expand_detail: expand_detail,
        expand_more_count: 3,
        expand_label: "Show details",
        collapse_label: "Hide details"
      ))
    end

    it "renders div[data-controller='pito--expand']" do
      expect(node.css("[data-controller='pito--expand']")).not_to be_empty
    end

    it "sets the expand label value on the controller element" do
      ctrl = node.css("[data-controller='pito--expand']").first
      expect(ctrl.to_html).to include("Show details")
    end

    it "sets a different collapse label value on the controller element" do
      ctrl = node.css("[data-controller='pito--expand']").first
      expect(ctrl.to_html).to include("Hide details")
    end

    it "expand label and collapse label are not the same value" do
      ctrl_html = node.css("[data-controller='pito--expand']").first.to_html
      expand_idx   = ctrl_html.index("Show details")
      collapse_idx = ctrl_html.index("Hide details")
      expect(expand_idx).not_to be_nil
      expect(collapse_idx).not_to be_nil
      expect(expand_idx).not_to eq(collapse_idx)
    end

    it "renders the hint target" do
      expect(node.css("[data-pito--expand-target='hint']")).not_to be_empty
    end

    it "renders ctrl+| in a yellow span inside the hint" do
      hint = node.css("[data-pito--expand-target='hint']").first
      expect(hint).not_to be_nil
      yellow = hint.css("span.text-yellow").first
      expect(yellow).not_to be_nil
      expect(yellow.text).to include("ctrl+|")
    end

    it "renders hintLabel target" do
      expect(node.css("[data-pito--expand-target='hintLabel']")).not_to be_empty
    end

    it "renders the detail target" do
      expect(node.css("[data-pito--expand-target='detail']")).not_to be_empty
    end

    it "detail target has hidden class" do
      detail = node.css("[data-pito--expand-target='detail']").first
      expect(detail["class"]).to include("hidden")
    end

    it "includes detail lines inside the detail target" do
      detail = node.css("[data-pito--expand-target='detail']").first
      expect(detail.text).to include("Item A: 2")
    end

    it "renders expand_lines before the hint" do
      html = node.to_html
      expand_line_idx = html.index("Summary line one")
      hint_idx        = html.index("ctrl+|")
      expect(expand_line_idx).not_to be_nil
      expect(hint_idx).not_to be_nil
      expect(expand_line_idx).to be < hint_idx
    end

    context "with structured KV rows in expand_detail" do
      let(:expand_detail) do
        [
          { key: "Subscribers", value: "1.5K" },
          { key: "Views",       value: "2.3M" },
          "",
          { key: "Videos", value: "42", key_class: "text-cyan", value_class: "text-fg-dim" }
        ]
      end

      it "renders KV rows with cyan key and dim value" do
        detail = node.css("[data-pito--expand-target='detail']").first
        rows = detail.css("div.flex")

        # First row: Subscribers
        first_row = rows[0]
        expect(first_row.css("span").first.text).to eq("Subscribers")
        expect(first_row.css("span").last.text).to eq("1.5K")

        # Second row: Views
        second_row = rows[1]
        expect(second_row.css("span").first.text).to eq("Views")
        expect(second_row.css("span").last.text).to eq("2.3M")

        # After spacer, Videos row with custom classes and fixed-width key + right-aligned value
        video_row = rows[2]
        key_span = video_row.css("span").first
        val_span = video_row.css("span").last
        expect(key_span["class"]).to include("text-cyan")
        expect(key_span["class"]).to include("w-40")
        expect(val_span["class"]).to include("text-fg")
        expect(val_span["class"]).to include("text-right")
        expect(val_span["class"]).to include("w-20")
      end
    end
  end
end
