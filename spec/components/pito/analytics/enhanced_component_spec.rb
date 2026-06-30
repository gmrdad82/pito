# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::EnhancedComponent do
  # Component specs get type: :component automatically (see rails_helper.rb).
  # render_inline returns a Nokogiri fragment. Use .css and .text for assertions.

  let(:intro) { "Boss Fight, by the numbers." }

  let(:full_metrics) do
    {
      views:             { current: 1234, previous: 1000 },
      watched_hours:     { current: 12.5, previous: 10.0 },
      avg_view_duration: { current: 245,  previous: 200 },
      avg_viewed_pct:    { current: 38.2, previous: 40.0 },
      subs_gained:       { current: 20,   previous: 10 },
      subs_lost:         { current: 9,    previous: 4 },
      likes:             { current: 210,  previous: 180 },
      dislikes:          { current: 4,    previous: 2 },
      comments:          { current: 31,   previous: 30 }
    }
  end

  let(:result) do
    Pito::Analytics::Scalars::Result.new(metrics: full_metrics, label: "28d", comparable: true)
  end

  # ── Pending state ────────────────────────────────────────────────────────────

  describe "pending mode" do
    subject(:node) { render_inline(described_class.new(intro: intro, pending: true)) }

    it "renders the intro text" do
      expect(node.text).to include(intro)
    end

    it "renders data-pito-ts-slot" do
      expect(node.css("[data-pito-ts-slot]")).not_to be_empty
    end

    it "renders the scalars table in loading state" do
      expect(node.css(".pito-analytics-scalars")).not_to be_empty
    end

    it "renders exactly 5 loading cells (one .pito-metric--nodata per metric)" do
      expect(node.css(".pito-metric--nodata").size).to eq(5)
    end

    it "renders loading dots in each of the 5 cells" do
      expect(node.css(".pito-loading-dots").size).to eq(5)
    end

    it "does not render the unavailable note" do
      expect(node.css(".pito-analytics-enhanced__note")).to be_empty
    end

    it "has the outer pito-analytics-enhanced class" do
      expect(node.css(".pito-analytics-enhanced")).not_to be_empty
    end

    context "with a token" do
      let(:token) { "abcd1234" }
      subject(:node) { render_inline(described_class.new(intro: intro, pending: true, token: token)) }

      it "wraps each loading cell in a div whose id matches <token>__metric_<key>" do
        expected_keys = %w[views watched_hours avg_view_duration subs_net likes]
        ids = node.css("div.pito-analytics-scalars__cell[id]").map { |d| d["id"] }
        expect(ids.size).to eq(5)
        expected_keys.each do |key|
          expect(ids).to include("#{token}__metric_#{key}")
        end
      end

      it "each cell id ends with one of the canonical metric keys" do
        ids = node.css("div.pito-analytics-scalars__cell[id]").map { |d| d["id"] }
        ids.each do |id|
          expect(id).to match(/__metric_(views|watched_hours|avg_view_duration|subs_net|likes)\z/)
        end
      end
    end

    it "renders an html_safe intro (subject-shimmer span) raw, not escaped" do
      html = Pito::Copy.render_html("pito.copy.analytics.intro", { title: "Lies of P" }, shimmer: [ :title ])
      node = render_inline(described_class.new(intro: html, pending: true))
      span = node.css(".pito-analytics-enhanced__intro span.pito-subject-shimmer").first
      expect(span).to be_present
      expect(span.text).to eq("Lies of P")
    end

    it "renders a plain (jsonb round-tripped) intro string raw so a stored shimmer span survives" do
      stored = Pito::Copy.render_html("pito.copy.analytics.intro", { title: "Lies of P" }, shimmer: [ :title ]).to_str
      node   = render_inline(described_class.new(intro: stored, pending: true))
      expect(node.css(".pito-analytics-enhanced__intro span.pito-subject-shimmer")).not_to be_empty
    end
  end

  # ── Ready state: Result present ──────────────────────────────────────────────

  describe "ready mode with a Scalars::Result" do
    subject(:node) { render_inline(described_class.new(intro: intro, result: result)) }

    it "renders the intro text" do
      expect(node.text).to include(intro)
    end

    it "renders the scalars table" do
      expect(node.css(".pito-analytics-scalars")).not_to be_empty
    end

    it "does not render the unavailable note" do
      expect(node.css(".pito-analytics-enhanced__note")).to be_empty
    end

    it "renders data-pito-ts-slot in the intro" do
      expect(node.css("[data-pito-ts-slot]")).not_to be_empty
    end

    context "with a token" do
      let(:token) { "deadbeef" }
      subject(:node) { render_inline(described_class.new(intro: intro, result: result, token: token)) }

      it "wraps each filled cell in a div whose id matches <token>__metric_<key>" do
        expected_keys = %w[views watched_hours avg_view_duration subs_net likes]
        ids = node.css("div.pito-analytics-scalars__cell[id]").map { |d| d["id"] }
        expect(ids.size).to eq(5)
        expected_keys.each do |key|
          expect(ids).to include("#{token}__metric_#{key}")
        end
      end

      it "each ready cell id ends with one of the canonical metric keys" do
        ids = node.css("div.pito-analytics-scalars__cell[id]").map { |d| d["id"] }
        ids.each do |id|
          expect(id).to match(/__metric_(views|watched_hours|avg_view_duration|subs_net|likes)\z/)
        end
      end

      it "uses the SAME dom-id format as the loading state (ids are stable across transitions)" do
        loading_node = render_inline(described_class.new(intro: intro, pending: true, token: token))
        loading_ids  = loading_node.css("div.pito-analytics-scalars__cell[id]").map { |d| d["id"] }.sort
        ready_ids    = node.css("div.pito-analytics-scalars__cell[id]").map { |d| d["id"] }.sort
        expect(ready_ids).to eq(loading_ids)
      end
    end
  end

  # ── Nudge (the "use analyze" line appended after the metrics) ─────────────────

  describe "nudge" do
    it "renders the nudge line after the panel when given" do
      node = render_inline(described_class.new(intro:, result:, nudge: "Want more? `analyze` it."))
      nudge = node.css(".pito-analytics-enhanced__nudge")
      expect(nudge).not_to be_empty
      expect(nudge.text).to include("analyze")
    end

    it "omits the nudge when none is given" do
      node = render_inline(described_class.new(intro:, result:))
      expect(node.css(".pito-analytics-enhanced__nudge")).to be_empty
    end

    it "does not render the nudge while pending" do
      node = render_inline(described_class.new(intro:, pending: true, nudge: "x"))
      expect(node.css(".pito-analytics-enhanced__nudge")).to be_empty
    end
  end

  # ── Unavailable state: result nil ────────────────────────────────────────────

  describe "unavailable mode (result: nil)" do
    subject(:node) { render_inline(described_class.new(intro: intro, result: nil)) }

    it "renders the intro text" do
      expect(node.text).to include(intro)
    end

    it "renders the unavailable note" do
      expect(node.css(".pito-analytics-enhanced__note")).not_to be_empty
    end

    it "does not render the scalars table" do
      expect(node.css(".pito-analytics-scalars")).to be_empty
    end
  end

  # ── Unavailable state: result :unavailable ───────────────────────────────────

  describe "unavailable mode (result: :unavailable)" do
    subject(:node) { render_inline(described_class.new(intro: intro, result: :unavailable)) }

    it "renders the unavailable note" do
      expect(node.css(".pito-analytics-enhanced__note")).not_to be_empty
    end

    it "does not render the scalars table" do
      expect(node.css(".pito-analytics-scalars")).to be_empty
    end

    it "renders the intro text" do
      expect(node.text).to include(intro)
    end
  end
end
