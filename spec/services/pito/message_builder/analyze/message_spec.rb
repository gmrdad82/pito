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
      expect(doc.css("span.pito-token-shimmer").map(&:text)).to include("7d")
    end

    it "body is a non-blank HTML string" do
      expect(payload["body"]).to be_a(String).and(be_present)
    end

    it "body does NOT include the scalars grid (still pending)" do
      expect(payload["body"]).not_to include("pito-analytics-scalars")
    end

    it "body includes the intro wrapper (pending ScaffoldComponent)" do
      expect(payload["body"]).to include("pito-analytics-enhanced__intro")
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
      subject(:ready) { described_class.ready_payload(pending_event, data: { scaffold: full_scaffold, views: nil }) }

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

      it "renders a '1' cell for each pulled metric" do
        doc    = Nokogiri::HTML.fragment(ready["body"])
        values = doc.css(".pito-analytics-scalars__value").map(&:text)
        expect(values).to all(eq("1"))
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

    context "with subscribed_status false in the scaffold" do
      subject(:ready) { described_class.ready_payload(pending_event, data: { scaffold: partial_scaffold, views: nil }) }

      it "renders subscribed_status cell with value '0'" do
        doc    = Nokogiri::HTML.fragment(ready["body"])
        values = doc.css(".pito-analytics-scalars__value").map(&:text)
        # subscribed_status is the last metric in SYSTEM order for channel level
        expect(values.last).to eq("0")
      end

      it "renders cells with '1' for the other metrics (views, etc.)" do
        doc    = Nokogiri::HTML.fragment(ready["body"])
        values = doc.css(".pito-analytics-scalars__value").map(&:text)
        # all except the last (subscribed_status) should be "1"
        expect(values[0..-2]).to all(eq("1"))
      end
    end

    context "with an empty scaffold (no data pulled)" do
      subject(:ready) { described_class.ready_payload(pending_event, data: { scaffold: {}, views: nil }) }

      it "sets analyze.status to 'ready'" do
        expect(ready.dig("analyze", "status")).to eq("ready")
      end

      it "body still includes the scalars grid" do
        expect(ready["body"]).to include("pito-analytics-scalars")
      end

      it "every cell value is '0'" do
        doc    = Nokogiri::HTML.fragment(ready["body"])
        values = doc.css(".pito-analytics-scalars__value").map(&:text)
        expect(values).not_to be_empty
        expect(values).to all(eq("0"))
      end
    end

    context "with enhanced role for channel level (retention excluded)" do
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

      subject(:ready) { described_class.ready_payload(enhanced_event, data: { scaffold: enhanced_scaffold, views: nil }) }

      it "sets analyze.status to 'ready'" do
        expect(ready.dig("analyze", "status")).to eq("ready")
      end

      it "retention is absent (vid_only metric skipped for channel)" do
        expect(ready["body"]).not_to include("retention")
      end

      it "renders '1' for devices and '0' for the rest" do
        doc    = Nokogiri::HTML.fragment(ready["body"])
        pairs  = doc.css(".pito-analytics-scalars__pair")
        # At least one cell present
        expect(pairs).not_to be_empty
        values = pairs.map { |p| p.at_css(".pito-analytics-scalars__value")&.text }
        expect(values).to include("1")
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
        data: { scaffold: full_scaffold, views: nil }
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

      it "only renders the views cell (active whitelist)" do
        doc    = Nokogiri::HTML.fragment(rerendered["body"])
        labels = doc.css(".pito-analytics-scalars__label").map(&:text)
        expect(labels).to eq([ "Views" ])
      end

      it "updates analyze.with to include 'views'" do
        expect(rerendered.dig("analyze", "with")).to eq([ "views" ])
      end

      it "sets analyze.without to []" do
        expect(rerendered.dig("analyze", "without")).to eq([])
      end
    end
  end
end
