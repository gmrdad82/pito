# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Analyze::Message do
  # ── ROLES constant ──────────────────────────────────────────────────────────

  describe "ROLES" do
    it "equals %w[system enhanced]" do
      expect(described_class::ROLES).to eq(%w[system enhanced])
    end
  end

  # ── .pending? ───────────────────────────────────────────────────────────────

  describe ".pending?" do
    it "returns true when payload has analyze.status == 'pending'" do
      event = instance_double("Event", payload: { "analyze" => { "status" => "pending" } })
      expect(described_class.pending?(event)).to be(true)
    end

    it "returns false when analyze.status is 'ready'" do
      event = instance_double("Event", payload: { "analyze" => { "status" => "ready" } })
      expect(described_class.pending?(event)).to be(false)
    end

    it "returns false when the payload has no analyze key" do
      event = instance_double("Event", payload: { "text" => "hello" })
      expect(described_class.pending?(event)).to be(false)
    end

    it "returns false when the payload is not a Hash" do
      event = instance_double("Event", payload: nil)
      expect(described_class.pending?(event)).to be(false)
    end

    it "returns true for a real pending payload built by .pending" do
      payload = described_class.pending(
        role: "system", title: "My Channel", level: :channel, entity_ids: [ 1 ], period: "7d",
        conversation: Conversation.singleton
      )
      event = instance_double("Event", payload: payload)
      expect(described_class.pending?(event)).to be(true)
    end
  end

  # ── .role ───────────────────────────────────────────────────────────────────

  describe ".role" do
    it "extracts the role from the analyze marker" do
      event = instance_double("Event", payload: { "analyze" => { "role" => "system" } })
      expect(described_class.role(event)).to eq("system")
    end

    it "returns 'enhanced' for the enhanced role" do
      event = instance_double("Event", payload: { "analyze" => { "role" => "enhanced" } })
      expect(described_class.role(event)).to eq("enhanced")
    end
  end

  # ── .pending ────────────────────────────────────────────────────────────────

  describe ".pending" do
    subject(:payload) do
      described_class.pending(
        role:         "system",
        title:        "My Channel",
        level:        :channel,
        entity_ids:   [ 42 ],
        period:       "7d",
        conversation: Conversation.singleton
      )
    end

    it "sets html: true" do
      expect(payload["html"]).to be(true)
    end

    it "sets anchor: true" do
      expect(payload["anchor"]).to be(true)
    end

    it "sets analyze.status to 'pending'" do
      expect(payload.dig("analyze", "status")).to eq("pending")
    end

    it "sets analyze.role to the provided role" do
      expect(payload.dig("analyze", "role")).to eq("system")
    end

    it "sets analyze.title to the provided title" do
      expect(payload.dig("analyze", "title")).to eq("My Channel")
    end

    it "sets analyze.level to string form of the level" do
      expect(payload.dig("analyze", "level")).to eq("channel")
    end

    it "sets analyze.entity_ids to the provided array" do
      expect(payload.dig("analyze", "entity_ids")).to eq([ 42 ])
    end

    it "sets analyze.period to the provided period" do
      expect(payload.dig("analyze", "period")).to eq("7d")
    end

    it "stores a non-blank intro in the marker" do
      expect(payload.dig("analyze", "intro")).to be_a(String).and(be_present)
    end

    it "renders the entity title as the subject (purple→blue shimmer)" do
      doc = Nokogiri::HTML.fragment(payload.dig("analyze", "intro"))
      expect(doc.css("span.pito-subject-shimmer").map(&:text)).to include("My Channel")
    end

    it "renders the period as a cyan reference token (distinct from the subject)" do
      doc = Nokogiri::HTML.fragment(payload.dig("analyze", "intro"))
      expect(doc.css("span.pito-token").map(&:text)).to include("7d")
    end

    it "body is a non-blank HTML string" do
      expect(payload["body"]).to be_a(String).and(be_present)
    end

    it "body includes the scalars grid with loading cells (progressive fan-out)" do
      expect(payload["body"]).to include("pito-analytics-scalars")
    end

    it "body includes the intro wrapper (pending ScaffoldComponent)" do
      expect(payload["body"]).to include("pito-analytics-enhanced__intro")
    end

    it "analyze.token is a non-blank hex string" do
      expect(payload.dig("analyze", "token")).to be_a(String).and(be_present)
    end

    it "analyze.metric_keys lists the ordered metrics for the role+level" do
      expected = Pito::Analytics::MetricOrder.for(role: :system, level: :channel).map(&:to_s)
      expect(payload.dig("analyze", "metric_keys")).to eq(expected)
    end

    it "body includes loading-cell swap targets for the first metric key" do
      token       = payload.dig("analyze", "token")
      first_key   = Pito::Analytics::MetricOrder.for(role: :system, level: :channel).first.to_s
      expect(payload["body"]).to include("#{token}__metric_#{first_key}")
    end

    it "stamps reply_target: 'analyze_message' (followupable)" do
      expect(payload["reply_target"]).to eq("analyze_message")
    end

    it "stamps a non-blank reply_handle (followupable)" do
      expect(payload["reply_handle"]).to be_a(String).and(be_present)
    end

    context "with the enhanced role" do
      subject(:payload) do
        described_class.pending(
          role: "enhanced", title: "My Channel", level: :channel, entity_ids: [ 42 ], period: "7d",
          conversation: Conversation.singleton
        )
      end

      it "sets analyze.role to 'enhanced'" do
        expect(payload.dig("analyze", "role")).to eq("enhanced")
      end
    end
  end

  # ── .ready_payload ──────────────────────────────────────────────────────────

  describe ".ready_payload" do
    # Build a pending event via the real .pending call so the stored analyze
    # marker (intro, role, level, etc.) is available for ready_payload to read.
    let(:pending_payload) do
      described_class.pending(
        role:         "system",
        title:        "My Channel",
        level:        :channel,
        entity_ids:   [ 42 ],
        period:       "7d",
        conversation: Conversation.singleton
      )
    end
    let(:pending_event) { instance_double("Event", payload: pending_payload) }
    let(:stored_intro)  { pending_payload.dig("analyze", "intro") }

    # All system metrics are "pulled" (true). channel level excludes retention.
    let(:full_scaffold) do
      Pito::Analytics::MetricOrder.for(role: :system, level: :channel).index_with { true }
    end

    # Scaffold with subscribed_status explicitly false; views true.
    let(:partial_scaffold) do
      Pito::Analytics::MetricOrder.for(role: :system, level: :channel)
        .index_with { true }
        .merge(subscribed_status: false)
    end

    context "with a full scaffold (all metrics pulled)" do
      subject(:ready) { described_class.ready_payload(pending_event, data: { scaffold: full_scaffold, charts: {} }) }

      it "sets analyze.status to 'ready'" do
        expect(ready.dig("analyze", "status")).to eq("ready")
      end

      it "preserves the role in the marker" do
        expect(ready.dig("analyze", "role")).to eq("system")
      end

      it "reuses the stored intro verbatim" do
        expect(ready.dig("analyze", "intro")).to eq(stored_intro)
      end

      it "sets html: true" do
        expect(ready["html"]).to be(true)
      end

      it "sets anchor: true" do
        expect(ready["anchor"]).to be(true)
      end

      it "body includes the scalars grid" do
        expect(ready["body"]).to include("pito-analytics-scalars")
      end

      it "renders every pulled :system metric as a chart/heart cell (no 0/1 scalars left)" do
        # With charts:{} but scaffold all-true, each :system metric (all Area/Heart)
        # renders as its NoData placeholder — there are no pure-scalar 0/1 cells.
        doc = Nokogiri::HTML.fragment(ready["body"])
        expect(doc.css(".pito-analytics-scalars__value")).to be_empty
        expect(ready["body"]).to include("pito-metric--nodata")
      end

      it "persists scaffold in marker['scaffold'] with string keys" do
        scaffold_in_marker = ready.dig("analyze", "scaffold")
        expect(scaffold_in_marker).to be_a(Hash)
        expect(scaffold_in_marker.keys).to all(be_a(String))
      end

      it "preserves the reply_handle from the source event" do
        original_handle = pending_payload["reply_handle"]
        expect(ready["reply_handle"]).to eq(original_handle)
      end

      it "preserves reply_target: 'analyze_message'" do
        expect(ready["reply_target"]).to eq("analyze_message")
      end
    end

    context "with no chart/heart data (system role)" do
      subject(:ready) { described_class.ready_payload(pending_event, data: { scaffold: partial_scaffold, charts: {} }) }

      it "renders NoData for the chart-type metrics (views/…/likes) that have no data" do
        # views/watched_hours/subs/avg_view_duration/avg_viewed_pct/likes are Area/Heart
        # metrics → with no data they become the NoData placeholder, not a 0/1 cell.
        expect(ready["body"]).to include("pito-metric--nodata")
      end

      it "leaves no 0/1 scalar cells (every :system metric is now an Area/Heart metric)" do
        # comments moved to :enhanced as an area chart, so :system is all chart/heart
        # metrics → all NoData with no data, no scalar value cells remain.
        doc = Nokogiri::HTML.fragment(ready["body"])
        expect(doc.css(".pito-analytics-scalars__value")).to be_empty
      end
    end

    context "with an empty scaffold (no data pulled)" do
      subject(:ready) { described_class.ready_payload(pending_event, data: { scaffold: {}, charts: {} }) }

      it "sets analyze.status to 'ready'" do
        expect(ready.dig("analyze", "status")).to eq("ready")
      end

      it "body still includes the scalars grid" do
        expect(ready["body"]).to include("pito-analytics-scalars")
      end

      it "renders no 0/1 scalar cells (system is all chart/heart metrics → NoData)" do
        doc = Nokogiri::HTML.fragment(ready["body"])
        expect(doc.css(".pito-analytics-scalars__value")).to be_empty
        expect(ready["body"]).to include("pito-metric--nodata")
      end
    end

    context "with enhanced role for channel level (retention now included)" do
      let(:enhanced_pending) do
        described_class.pending(
          role: "enhanced", title: "My Channel", level: :channel, entity_ids: [ 42 ], period: "7d",
          conversation: Conversation.singleton
        )
      end
      let(:enhanced_event) { instance_double("Event", payload: enhanced_pending) }
      let(:enhanced_scaffold) do
        Pito::Analytics::MetricOrder.for(role: :enhanced, level: :channel).index_with { |m| m == :devices }
      end

      subject(:ready) { described_class.ready_payload(enhanced_event, data: { scaffold: enhanced_scaffold, charts: {} }) }

      it "sets analyze.status to 'ready'" do
        expect(ready.dig("analyze", "status")).to eq("ready")
      end

      it "retention is now available at channel level (aggregated from the channel's vids)" do
        expect(Pito::Analytics::MetricOrder.for(role: :enhanced, level: :channel)).to include(:retention)
      end

      it "renders the enhanced metrics (bars/retention/heatmap/comments) as NoData when no data is supplied" do
        # devices/geography/demographics_* (Bar), retention/comments (Area), and
        # day_of_week_heatmap (Heatmap) all become the NoData placeholder with no data;
        # none is a 0/1 scaffold cell.
        doc = Nokogiri::HTML.fragment(ready["body"])
        expect(ready["body"]).to include("pito-metric--nodata")
        expect(doc.css(".pito-analytics-scalars__value")).to be_empty
      end
    end

    context "with chart data for views/watched_hours/subs (AreaChart cells)" do
      let(:views_chart)        { { "series" => [ 1, 2, 3 ], "total" => 6, "previous" => 4, "target_daily" => 1.0 } }
      let(:watched_hours_chart) { { "series" => [ 0.1, 0.2 ], "total" => 0.3, "previous" => nil, "target_daily" => 0.05 } }
      let(:subs_chart)         { { "series" => [ 2, -1, 3 ], "total" => 4, "previous" => 2, "target_daily" => 0.14 } }

      subject(:ready) do
        described_class.ready_payload(
          pending_event,
          data: {
            scaffold: full_scaffold,
            charts: {
              views:         views_chart,
              watched_hours: watched_hours_chart,
              subs:          subs_chart
            }
          }
        )
      end

      it "persists all three charts in the marker with captions" do
        %w[views watched_hours subs].each do |key|
          expect(ready.dig("analyze", key)).to be_a(Hash)
          expect(ready.dig("analyze", key, "caption")).to be_a(String).and(be_present)
        end
      end

      it "body renders AreaChart components (no scalar value cells for chart metrics)" do
        doc    = Nokogiri::HTML.fragment(ready["body"])
        charts = doc.css(".pito-metric--area-chart")
        expect(charts.size).to eq(3)
      end

      it "renders the remaining system metrics as NoData (no scalar cells left)" do
        doc = Nokogiri::HTML.fragment(ready["body"])
        # chart metrics (views/watched_hours/subs) → AreaChart (3); the remaining
        # :system metrics (avg_view_duration/avg_viewed_pct/likes) have no data →
        # NoData; there are no 0/1 scalar cells.
        expect(doc.css(".pito-metric--area-chart").size).to eq(3)
        expect(doc.css(".pito-analytics-scalars__value")).to be_empty
      end

      it "cells_for produces chart cells for chart metrics and scaffold cells for others" do
        metrics = Pito::Analytics::MetricOrder.for(role: :system, level: :channel)
        chart_metrics = %i[views watched_hours subs] & metrics
        selection = Pito::Analytics::MetricSelection.from_lists([], [])
        cells = described_class.cells_for(
          role: "system", level: "channel",
          scaffold: full_scaffold, selection:,
          charts: { views: views_chart, watched_hours: watched_hours_chart, subs: subs_chart },
          chart_captions: {}
        )
        chart_cells  = cells.select { |c| c[:chart].present? }
        scalar_cells = cells.reject { |c| c[:chart].present? }
        expect(chart_cells.map { |c| c[:chart] }).to match_array(chart_metrics)
        expect(scalar_cells.size).to eq(metrics.size - chart_metrics.size)
        # Distinct metric symbols in each chart cell
        expect(chart_cells.map { |c| c[:chart] }.uniq.size).to eq(chart_cells.size)
      end
    end
  end

  # ── .render_chart_caption ──────────────────────────────────────────────────

  describe ".render_chart_caption" do
    context "for avg_viewed_pct (PULLED from YouTube averageViewPercentage)" do
      let(:chart) do
        {
          "series"          => [ 40.0, 45.0, 50.0 ],
          "total_pct"       => 45.2,
          "previous"        => nil,
          "trend"           => false,
          "reference_token" => nil
        }
      end

      it "renders the views-weighted percentage as the caption value" do
        html = described_class.render_chart_caption(metric: :avg_viewed_pct, chart:)
        expect(html).to include("45.2%")
      end

      it "renders no second insight row (that derived feature was dropped)" do
        html = described_class.render_chart_caption(metric: :avg_viewed_pct, chart:)
        expect(html).not_to include("<br>")
      end
    end

    context "for day_of_week_heatmap" do
      it "names the busiest weekday as a subject-shimmer token" do
        html = described_class.render_chart_caption(
          metric: :day_of_week_heatmap,
          chart:  { "values" => [ 10.0, 20.0, 5.0, 30.0, 25.0, 40.0, 15.0 ] }
        )
        # Saturday (index 5) is the max → the caption subject.
        expect(Nokogiri::HTML.fragment(html).css("span.pito-subject-shimmer").map(&:text)).to include("Saturday")
      end
    end

    context "for views (NOT avg_viewed_pct)" do
      let(:chart) { { "series" => [ 100, 200 ], "total" => 300, "previous" => 200, "target_daily" => 50.0 } }

      it "does NOT render the insight row" do
        html = described_class.render_chart_caption(metric: :views, chart:)
        expect(html).not_to include("<br>")
      end
    end
  end

  # ── .pair ──────────────────────────────────────────────────────────────────

  describe ".pair" do
    let(:conversation) { Conversation.singleton }

    subject(:pair) do
      described_class.pair(
        level:        :channel,
        entity_ids:   [ 42 ],
        title:        "My Channel",
        period:       "7d",
        conversation:
      )
    end

    it "returns exactly two elements" do
      expect(pair.length).to eq(2)
    end

    it "first element has kind :system" do
      expect(pair.first[:kind]).to eq(:system)
    end

    it "second element has kind :enhanced" do
      expect(pair.second[:kind]).to eq(:enhanced)
    end

    it "both payloads have analyze.status 'pending'" do
      pair.each do |item|
        expect(item[:payload].dig("analyze", "status")).to eq("pending")
      end
    end

    it "both payloads are followupable (reply_target: 'analyze_message')" do
      pair.each do |item|
        expect(item[:payload]["reply_target"]).to eq("analyze_message")
        expect(item[:payload]["reply_handle"]).to be_present
      end
    end

    it "each event gets a distinct reply_handle" do
      handles = pair.map { |item| item[:payload]["reply_handle"] }
      expect(handles.uniq.length).to eq(2)
    end

    it "the :system card keeps the shift+space period; the :enhanced card is always lifetime" do
      system_marker   = pair.first[:payload]["analyze"]
      enhanced_marker = pair.second[:payload]["analyze"]
      expect(system_marker["period"]).to eq("7d")
      expect(enhanced_marker["period"]).to eq("lifetime")
    end

    it "the :enhanced intro references lifetime (not the shift+space period)" do
      intro = pair.second[:payload]["analyze"]["intro"]
      expect(intro).to include("lifetime")
      expect(intro).not_to include("7d")
    end
  end

  # ── .rerender ──────────────────────────────────────────────────────────────

  describe ".rerender" do
    let(:conversation) { Conversation.singleton }

    let(:pending_payload) do
      described_class.pending(
        role:         "system",
        title:        "My Channel",
        level:        :channel,
        entity_ids:   [ 42 ],
        period:       "7d",
        conversation:
      )
    end

    let(:full_scaffold) do
      Pito::Analytics::MetricOrder.for(role: :system, level: :channel).index_with { true }
    end

    let(:ready_payload) do
      described_class.ready_payload(
        instance_double("Event", payload: pending_payload),
        data: { scaffold: full_scaffold, charts: {} }
      )
    end

    let(:ready_event) { instance_double("Event", payload: ready_payload) }

    context "with without: [:comments]" do
      subject(:rerendered) { described_class.rerender(ready_event, with: [], without: [ :comments ]) }

      it "excludes the comments cell from the rendered body" do
        expect(rerendered["body"]).not_to include("Comments")
      end

      it "still renders other metric cells (e.g. Views)" do
        expect(rerendered["body"]).to include("Views")
      end

      it "updates analyze.without to include 'comments' (string)" do
        expect(rerendered.dig("analyze", "without")).to eq([ "comments" ])
      end

      it "preserves the reply_handle from the source event" do
        expect(rerendered["reply_handle"]).to eq(ready_payload["reply_handle"])
      end

      it "preserves reply_target: 'analyze_message'" do
        expect(rerendered["reply_target"]).to eq("analyze_message")
      end

      it "body still includes the scalars grid wrapper" do
        expect(rerendered["body"]).to include("pito-analytics-scalars")
      end
    end

    context "with with: [:views], without: []" do
      subject(:rerendered) { described_class.rerender(ready_event, with: [ :views ], without: []) }

      it "renders only the views metric — as NoData, since no chart data was supplied" do
        # whitelist = views only; views is an Area metric with no data here → NoData
        # placeholder (its label rides along as the caption). No other metric cells.
        expect(rerendered["body"].scan("pito-metric--nodata").size).to eq(1)
        expect(rerendered["body"]).to include("Views")
      end

      it "updates analyze.with to include 'views'" do
        expect(rerendered.dig("analyze", "with")).to eq([ "views" ])
      end

      it "sets analyze.without to []" do
        expect(rerendered.dig("analyze", "without")).to eq([])
      end
    end
  end

  describe ".bar_cell / .bar_presentation" do
    def bars_for(metric, rows) = described_class.bar_cell(metric, rows, "cap")[:bars]

    it "subscribed_status: Not subscribed (red) then Subscribed (green), with pct value labels" do
      bars = bars_for(:subscribed_status, [ { key: "UNSUBSCRIBED", pct: 93.2 }, { key: "SUBSCRIBED", pct: 6.8 } ])
      expect(bars).to eq([
        { label: "Not subscribed", color: :red,   pct: 93.2, value_label: "93.2%" },
        { label: "Subscribed",     color: :green, pct: 6.8,  value_label: "6.8%" }
      ])
    end

    it "devices: Mobile/Computer/TV mapped to blue/purple/cyan" do
      bars = bars_for(:devices, [ { "key" => "MOBILE", "pct" => 70.0 }, { "key" => "DESKTOP", "pct" => 25.0 }, { "key" => "TV", "pct" => 5.0 } ])
      expect(bars.map { |b| [ b[:label], b[:color] ] }).to eq([ [ "Mobile", :blue ], [ "Computer", :purple ], [ "TV", :cyan ] ])
    end

    it "gender: maps known keys + falls back unknown gender → Other/purple" do
      bars = bars_for(:demographics_gender, [ { key: "female", pct: 60.0 }, { key: "weird", pct: 40.0 } ])
      expect(bars.map { |b| [ b[:label], b[:color] ] }).to eq([ [ "Female", :pink ], [ "Other", :purple ] ])
    end

    it "age: strips the age prefix, en-dashes ranges, and renders 65- as 65+ with a colour ramp" do
      bars = bars_for(:demographics_age, [ { key: "age25-34", pct: 45.0 }, { key: "age65-", pct: 5.0 } ])
      expect(bars.map { |b| [ b[:label], b[:color] ] }).to eq([ [ "25–34", :cyan ], [ "65+", :blue ] ])
    end

    it "geography: resolves the country code to a name and colours by order from the ramp" do
      bars = bars_for(:geography, [ { key: "us", pct: 60.0 }, { key: "gb", pct: 15.0 } ])
      expect(bars.map { |b| [ b[:label], b[:color] ] }).to eq([ [ "United States", :green ], [ "United Kingdom", :cyan ] ])
    end
  end

  # ── retention caption (Item 25) ────────────────────────────────────────────────

  describe ".render_chart_caption for :retention" do
    let(:chart) { { "total_pct" => 27.9, "benchmark_word" => "above average", "series" => [ 80, 60, 40 ] } }

    it "uses retention's OWN caption pool (not the generic metric_caption)" do
      html = described_class.render_chart_caption(metric: :retention, chart:).to_s
      expect(html).to include("28%")                          # mean retention %, rounded + shimmered
      expect(html).to include("pito-subject-shimmer")         # value rendered as a subject token
      expect(html).to include("above average")                # benchmark word
      expect(html).to include("pito-trend-number--up")        # benchmark in its trend colour
    end

    it "is a distinct metric — CHART_METRIC_KEYS includes retention" do
      expect(described_class::CHART_METRIC_KEYS).to include("retention")
    end
  end
end
