# frozen_string_literal: true

require "rails_helper"

# Handler for the `analyze` chat verb. On a resolvable scope it parses a
# SegmentSelection (`numbers` → :system card, `breakdowns` → :enhanced card) and
# emits ONLY the selected pending events for AnalyzePrepareJob to fill
# (plan-0.9.5 D3): bare `analyze` → numbers only; `full` → both; `only`/`with`
# per the clause. Metric tokens are fed to SegmentSelection as extra_vocabulary
# so they never read as unknown segments. Bare `analyze` returns the suggest
# copy; an unresolvable scope / conflicting / unknown segment surfaces the
# matching error copy.
RSpec.describe Pito::Chat::Handlers::Analyze do
  def analyze(input, channel: "@all")
    msg = Pito::Chat::Parser.call(
      Pito::Lex::Lexer.call(input), raw: input, conversation: Conversation.singleton
    )
    described_class.new(message: msg, conversation: Conversation.singleton, channel:).call
  end

  def text(result)
    payload = result.events.first[:payload]
    payload[:text] || payload["text"]
  end

  it "nudges with the suggest copy for bare `analyze`" do
    expect(text(analyze("analyze"))).to include("Analyze what?")
  end

  it "surfaces the not-found error for an unknown channel handle" do
    expect(text(analyze("analyze channel @ghost"))).to include("@ghost")
  end

  it "surfaces the not-found error for unknown vid ids" do
    expect(text(analyze("analyze vids #999999"))).to include("#999999")
  end

  context "with a resolvable channel scope" do
    let!(:channel) { create(:channel, handle: "gmrdad82") }

    # Bare `analyze` → the numbers (:system) card only (plan-0.9.5 D3).
    context "bare (numbers only)" do
      subject(:result) { analyze("analyze channel @gmrdad82") }

      it "returns exactly one event" do
        expect(result.events.length).to eq(1)
      end

      it "the single event is the :system (numbers) card" do
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload].dig("analyze", "role")).to eq("system")
      end

      it "the event has analyze.status 'pending'" do
        expect(result.events.first[:payload].dig("analyze", "status")).to eq("pending")
      end

      it "the event records the channel entity id + level 'channel'" do
        marker = result.events.first[:payload]["analyze"]
        expect(marker["entity_ids"]).to include(channel.id)
        expect(marker["level"]).to eq("channel")
      end

      it "the event is followupable (reply_target: 'analyze_message') with a non-blank reply_handle" do
        expect(result.events.first[:payload]["reply_target"]).to eq("analyze_message")
        expect(result.events.first[:payload]["reply_handle"]).to be_a(String).and(be_present)
      end
    end

    # `full` → both cards, in canonical order (today's output).
    context "full (both cards)" do
      subject(:result) { analyze("analyze channel @gmrdad82 full") }

      it "returns exactly two events" do
        expect(result.events.length).to eq(2)
      end

      it "first event has kind :system / role 'system'" do
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload].dig("analyze", "role")).to eq("system")
      end

      it "second event has kind :enhanced / role 'enhanced'" do
        expect(result.events.second[:kind]).to eq(:enhanced)
        expect(result.events.second[:payload].dig("analyze", "role")).to eq("enhanced")
      end

      it "both events have analyze.status 'pending'" do
        result.events.each do |event|
          expect(event[:payload].dig("analyze", "status")).to eq("pending")
        end
      end

      it "both events store a non-blank intro" do
        result.events.each do |event|
          expect(event[:payload].dig("analyze", "intro")).to be_a(String).and(be_present)
        end
      end

      it "both events record the channel entity id + level 'channel'" do
        result.events.each do |event|
          expect(event[:payload].dig("analyze", "entity_ids")).to include(channel.id)
          expect(event[:payload].dig("analyze", "level")).to eq("channel")
        end
      end

      it "both events are followupable with distinct, non-blank reply_handles" do
        handles = result.events.map { |e| e[:payload]["reply_handle"] }
        result.events.each { |e| expect(e[:payload]["reply_target"]).to eq("analyze_message") }
        expect(handles).to all(be_a(String).and(be_present))
        expect(handles.uniq.length).to eq(2)
      end
    end

    # `only breakdowns` → the breakdowns (:enhanced) card only.
    context "only breakdowns (enhanced only)" do
      subject(:result) { analyze("analyze channel @gmrdad82 only breakdowns") }

      it "returns exactly one event, the :enhanced (breakdowns) card" do
        expect(result.events.length).to eq(1)
        expect(result.events.first[:kind]).to eq(:enhanced)
        expect(result.events.first[:payload].dig("analyze", "role")).to eq("enhanced")
      end
    end

    # `with breakdowns` → defaults (numbers) + breakdowns → both cards.
    context "with breakdowns (numbers + breakdowns)" do
      subject(:result) { analyze("analyze channel @gmrdad82 with breakdowns") }

      it "returns both cards in canonical order" do
        expect(result.events.map { |e| e[:payload].dig("analyze", "role") }).to eq(%w[system enhanced])
      end
    end

    # A metric token (`views`) belongs to MetricSelection, not SegmentSelection —
    # it must NOT read as an unknown segment; bare-clause `with views` keeps
    # numbers only (no extra segment requested).
    context "with a metric token (views)" do
      subject(:result) { analyze("analyze channel @gmrdad82 with views") }

      it "is not an error and emits numbers only" do
        expect(result).to be_a(Pito::Chat::Result::Ok)
        expect(result.events.map { |e| e[:payload].dig("analyze", "role") }).to eq(%w[system])
      end
    end

    # Conflicting introducers (full + only) → the shared conflict error copy.
    context "conflicting selectors (full + only)" do
      subject(:result) { analyze("analyze channel @gmrdad82 full only breakdowns") }

      it "returns an Error result" do
        expect(result).to be_a(Pito::Chat::Result::Error)
      end
    end

    # An unknown segment token → the shared unknown error copy naming the token.
    context "unknown segment token" do
      subject(:result) { analyze("analyze channel @gmrdad82 only bogus") }

      it "returns an Error result naming the unknown token" do
        expect(result).to be_a(Pito::Chat::Result::Error)
        # segment_unknown_error stores the ALREADY-rendered copy in message_key.
        expect(result.message_key).to include("bogus")
      end
    end

    # `without breakdowns` → the numbers (:system) card only — segment excluded.
    context "without breakdowns (numbers only)" do
      subject(:result) { analyze("analyze channel @gmrdad82 without breakdowns") }

      it "returns exactly one event, the :system (numbers) card" do
        expect(result.events.length).to eq(1)
        expect(result.events.first[:kind]).to eq(:system)
        expect(result.events.first[:payload].dig("analyze", "role")).to eq("system")
      end
    end

    # `without comments` → metric token silently passed to MetricSelection;
    # segment selection returns full base (both cards). Pin this behavior.
    context "without a metric token (comments) — both cards emitted" do
      subject(:result) { analyze("analyze channel @gmrdad82 without comments") }

      it "is not an error (Ok result)" do
        expect(result).to be_a(Pito::Chat::Result::Ok)
      end

      it "emits both cards (metric token passes through to MetricSelection, segment base = full)" do
        expect(result.events.map { |e| e[:payload].dig("analyze", "role") }).to eq(%w[system enhanced])
      end
    end

    # `without` + `only` is a conflict.
    context "conflicting selectors (without + only)" do
      subject(:result) { analyze("analyze channel @gmrdad82 without breakdowns only numbers") }

      it "returns an Error result" do
        expect(result).to be_a(Pito::Chat::Result::Error)
      end
    end

    # ── D18: segments footer on the first emitted message ──────────────────────────

    context "segments footer (D18)" do
      # Bare `analyze channel` → numbers only in selection, so 1 addable (breakdowns) and 1 removable (numbers).
      it "bare analyze: first event has list_footer naming the addable segment (breakdowns)" do
        result  = analyze("analyze channel @gmrdad82")
        footer  = result.events.first[:payload]["list_footer"].to_s
        expect(footer).to include("breakdowns")
      end

      # full → both in selection, so 0 addable and 2 removable.
      it "full analyze: first event has list_footer with both segments as removable" do
        result  = analyze("analyze channel @gmrdad82 full")
        footer  = result.events.first[:payload]["list_footer"].to_s
        expect(footer).to include("numbers")
        expect(footer).to include("breakdowns")
        expect(footer).to include("nothing")
      end

      it "footer uses 'segments' as the noun" do
        result = analyze("analyze channel @gmrdad82")
        expect(result.events.first[:payload]["list_footer"].to_s).to include("segments")
      end
    end
  end
end
