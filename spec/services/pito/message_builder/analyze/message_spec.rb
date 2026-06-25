# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Analyze::Message do
  # Canonical full-metrics Result for ready-payload tests.
  let(:scalars_result) do
    Pito::Analytics::Scalars::Result.new(
      metrics: {
        views:             { current: 1234, previous: 1000 },
        watched_hours:     { current: 12.5, previous: 10.0 },
        avg_view_duration: { current: 245,  previous: 200  },
        avg_viewed_pct:    { current: 38.2, previous: 40.0 },
        subs_gained:       { current: 20,   previous: 10   },
        subs_lost:         { current: 9,    previous: 4    },
        likes:             { current: 210,  previous: 180  },
        dislikes:          { current: 4,    previous: 2    },
        comments:          { current: 31,   previous: 30   }
      },
      label:      "7d",
      comparable: true
    )
  end

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
        role: "system", title: "My Channel", level: :channel, entity_ids: [ 1 ], period: "7d"
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
        role:       "system",
        title:      "My Channel",
        level:      :channel,
        entity_ids: [ 42 ],
        period:     "7d"
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

    it "body is a non-blank HTML string" do
      expect(payload["body"]).to be_a(String).and(be_present)
    end

    it "body does NOT include the scalars table (still pending)" do
      expect(payload["body"]).not_to include("pito-analytics-scalars")
    end

    it "body does NOT include the unavailable note (still pending)" do
      expect(payload["body"]).not_to include("pito-analytics-enhanced__note")
    end

    context "with the enhanced role" do
      subject(:payload) do
        described_class.pending(
          role: "enhanced", title: "My Channel", level: :channel, entity_ids: [ 42 ], period: "7d"
        )
      end

      it "sets analyze.role to 'enhanced'" do
        expect(payload.dig("analyze", "role")).to eq("enhanced")
      end
    end
  end

  # ── .ready_payload ──────────────────────────────────────────────────────────

  describe ".ready_payload" do
    # Use a real persisted-style event: the payload is the output of .pending so
    # ready_payload can read the stored analyze marker (intro, etc.).
    let(:pending_payload) do
      described_class.pending(
        role:       "enhanced",
        title:      "My Channel",
        level:      :channel,
        entity_ids: [ 42 ],
        period:     "7d"
      )
    end
    let(:pending_event) { instance_double("Event", payload: pending_payload) }
    let(:stored_intro)  { pending_payload.dig("analyze", "intro") }

    context "with a Scalars::Result" do
      subject(:ready) { described_class.ready_payload(pending_event, result: scalars_result) }

      it "sets analyze.status to 'ready'" do
        expect(ready.dig("analyze", "status")).to eq("ready")
      end

      it "preserves the role in the marker" do
        expect(ready.dig("analyze", "role")).to eq("enhanced")
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

      it "body includes the scalars table" do
        expect(ready["body"]).to include("pito-analytics-scalars")
      end

      it "body does NOT include the unavailable note" do
        expect(ready["body"]).not_to include("pito-analytics-enhanced__note")
      end
    end

    context "with Scalars::UNAVAILABLE" do
      subject(:ready) do
        described_class.ready_payload(pending_event, result: Pito::Analytics::Scalars::UNAVAILABLE)
      end

      it "sets analyze.status to 'ready'" do
        expect(ready.dig("analyze", "status")).to eq("ready")
      end

      it "reuses the stored intro verbatim" do
        expect(ready.dig("analyze", "intro")).to eq(stored_intro)
      end

      it "body includes the unavailable note" do
        expect(ready["body"]).to include("pito-analytics-enhanced__note")
      end

      it "body does NOT include the scalars table" do
        expect(ready["body"]).not_to include("pito-analytics-scalars")
      end
    end
  end
end
