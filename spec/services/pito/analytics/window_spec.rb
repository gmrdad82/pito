# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::Window, type: :service do
  # Fixed reference date so every assertion is deterministic.
  let(:ref) { Date.new(2026, 6, 20) }

  describe "CYCLE" do
    it "contains the expected ordered tokens" do
      expect(described_class::CYCLE).to eq(%w[7d 28d 3m 1y lifetime m0 m1 m2 y0 y1])
    end

    it "does not include 1m" do
      expect(described_class::CYCLE).not_to include("1m")
    end
  end

  describe ".for" do
    context "with unknown token" do
      it "raises ArgumentError" do
        expect { described_class.for("1m", reference_date: ref) }
          .to raise_error(ArgumentError, /unknown analytics token/)
      end

      it "includes the bad token in the error message" do
        expect { described_class.for("bogus", reference_date: ref) }
          .to raise_error(ArgumentError, /"bogus"/)
      end
    end

    context "7d" do
      subject(:window) { described_class.for("7d", reference_date: ref) }

      it { expect(window.start_date).to eq(Date.new(2026, 6, 14)) }
      it { expect(window.end_date).to eq(Date.new(2026, 6, 20)) }
      it { expect(window.prev_start).to eq(Date.new(2026, 6, 7)) }
      it { expect(window.prev_end).to eq(Date.new(2026, 6, 13)) }
      it { expect(window.label).to eq("7d") }
      it { expect(window.comparable?).to be true }
      it { expect(window.token).to eq("7d") }

      it "window spans exactly 7 days (inclusive)" do
        expect(window.end_date - window.start_date + 1).to eq(7)
      end

      it "prev window spans exactly 7 days (inclusive)" do
        expect(window.prev_end - window.prev_start + 1).to eq(7)
      end

      it "prev window is immediately before current window" do
        expect(window.prev_end).to eq(window.start_date - 1)
      end
    end

    context "28d" do
      subject(:window) { described_class.for("28d", reference_date: ref) }

      it { expect(window.start_date).to eq(Date.new(2026, 5, 24)) }
      it { expect(window.end_date).to eq(Date.new(2026, 6, 20)) }
      it { expect(window.prev_start).to eq(Date.new(2026, 4, 26)) }
      it { expect(window.prev_end).to eq(Date.new(2026, 5, 23)) }
      it { expect(window.label).to eq("28d") }
      it { expect(window.comparable?).to be true }

      it "window spans exactly 28 days (inclusive)" do
        expect(window.end_date - window.start_date + 1).to eq(28)
      end

      it "prev window spans exactly 28 days (inclusive)" do
        expect(window.prev_end - window.prev_start + 1).to eq(28)
      end

      it "prev window is immediately before current window" do
        expect(window.prev_end).to eq(window.start_date - 1)
      end
    end

    context "3m" do
      subject(:window) { described_class.for("3m", reference_date: ref) }

      # ref=2026-06-20; (ref << 3)=2026-03-20; start=2026-03-21
      it { expect(window.start_date).to eq(Date.new(2026, 3, 21)) }
      it { expect(window.end_date).to eq(Date.new(2026, 6, 20)) }
      # prev_end = start-1 = 2026-03-20; (prev_end << 3)=2025-12-20; prev_start=2025-12-21
      it { expect(window.prev_start).to eq(Date.new(2025, 12, 21)) }
      it { expect(window.prev_end).to eq(Date.new(2026, 3, 20)) }
      it { expect(window.label).to eq("3m") }
      it { expect(window.comparable?).to be true }

      it "prev window is immediately before current window" do
        expect(window.prev_end).to eq(window.start_date - 1)
      end
    end

    context "1y" do
      subject(:window) { described_class.for("1y", reference_date: ref) }

      # ref=2026-06-20; (ref << 12)=2025-06-20; start=2025-06-21
      it { expect(window.start_date).to eq(Date.new(2025, 6, 21)) }
      it { expect(window.end_date).to eq(Date.new(2026, 6, 20)) }
      # prev_end=2025-06-20; (prev_end << 12)=2024-06-20; prev_start=2024-06-21
      it { expect(window.prev_start).to eq(Date.new(2024, 6, 21)) }
      it { expect(window.prev_end).to eq(Date.new(2025, 6, 20)) }
      it { expect(window.label).to eq("1y") }
      it { expect(window.comparable?).to be true }

      it "prev window is immediately before current window" do
        expect(window.prev_end).to eq(window.start_date - 1)
      end
    end

    context "lifetime" do
      context "without channel_created_on" do
        subject(:window) { described_class.for("lifetime", reference_date: ref) }

        it { expect(window.start_date).to eq(Date.new(2005, 1, 1)) }
        it { expect(window.end_date).to eq(Date.new(2026, 6, 20)) }
        it { expect(window.prev_start).to be_nil }
        it { expect(window.prev_end).to be_nil }
        it { expect(window.label).to eq("lifetime") }
        it { expect(window.comparable?).to be false }
      end

      context "with channel_created_on" do
        subject(:window) do
          described_class.for("lifetime", reference_date: ref, channel_created_on: Date.new(2020, 3, 15))
        end

        it { expect(window.start_date).to eq(Date.new(2020, 3, 15)) }
        it { expect(window.end_date).to eq(Date.new(2026, 6, 20)) }
        it { expect(window.comparable?).to be false }
      end
    end

    context "m0 (current partial month)" do
      subject(:window) { described_class.for("m0", reference_date: ref) }

      # ref=2026-06-20; bom=2026-06-01; prev_bom=2026-05-01; elapsed=19; prev_end=2026-05-20
      it { expect(window.start_date).to eq(Date.new(2026, 6, 1)) }
      it { expect(window.end_date).to eq(Date.new(2026, 6, 20)) }
      it { expect(window.prev_start).to eq(Date.new(2026, 5, 1)) }
      it { expect(window.prev_end).to eq(Date.new(2026, 5, 20)) }
      it { expect(window.label).to eq("Jun '26") }
      it { expect(window.comparable?).to be true }

      it "prev window covers the same number of days (same elapsed span)" do
        current_span = window.end_date - window.start_date
        prev_span    = window.prev_end - window.prev_start
        expect(prev_span).to eq(current_span)
      end

      context "when reference is the last day of a 31-day month and prev month has 28 days" do
        # e.g. ref=2025-03-31; prev month=Feb 2025 (28 days)
        let(:ref) { Date.new(2025, 3, 31) }

        it "clamps prev_end to end of February" do
          window = described_class.for("m0", reference_date: ref)
          expect(window.prev_end).to eq(Date.new(2025, 2, 28))
        end

        it "keeps prev_start at Feb 1" do
          window = described_class.for("m0", reference_date: ref)
          expect(window.prev_start).to eq(Date.new(2025, 2, 1))
        end
      end
    end

    context "m1 (last full month)" do
      subject(:window) { described_class.for("m1", reference_date: ref) }

      # ref=2026-06-20; bom=2026-06-01; m1=May 2026; prev=Apr 2026
      it { expect(window.start_date).to eq(Date.new(2026, 5, 1)) }
      it { expect(window.end_date).to eq(Date.new(2026, 5, 31)) }
      it { expect(window.prev_start).to eq(Date.new(2026, 4, 1)) }
      it { expect(window.prev_end).to eq(Date.new(2026, 4, 30)) }
      it { expect(window.label).to eq("May '26") }
      it { expect(window.comparable?).to be true }
    end

    context "m2 (two months ago, full)" do
      subject(:window) { described_class.for("m2", reference_date: ref) }

      # ref=2026-06-20; bom=2026-06-01; m2=Apr 2026; prev=Mar 2026
      it { expect(window.start_date).to eq(Date.new(2026, 4, 1)) }
      it { expect(window.end_date).to eq(Date.new(2026, 4, 30)) }
      it { expect(window.prev_start).to eq(Date.new(2026, 3, 1)) }
      it { expect(window.prev_end).to eq(Date.new(2026, 3, 31)) }
      it { expect(window.label).to eq("Apr '26") }
      it { expect(window.comparable?).to be true }
    end

    context "y0 (current partial year)" do
      subject(:window) { described_class.for("y0", reference_date: ref) }

      # ref=2026-06-20; boy=2026-01-01; elapsed=170; prev_boy=2025-01-01; prev_end=2025-06-20
      it { expect(window.start_date).to eq(Date.new(2026, 1, 1)) }
      it { expect(window.end_date).to eq(Date.new(2026, 6, 20)) }
      it { expect(window.prev_start).to eq(Date.new(2025, 1, 1)) }
      it { expect(window.prev_end).to eq(Date.new(2025, 6, 20)) }
      it { expect(window.label).to eq("2026") }
      it { expect(window.comparable?).to be true }

      it "prev window covers the same number of elapsed days" do
        current_elapsed = window.end_date - window.start_date
        prev_elapsed    = window.prev_end - window.prev_start
        expect(prev_elapsed).to eq(current_elapsed)
      end

      context "when reference is 2024-03-01 (leap year context)" do
        let(:ref) { Date.new(2024, 3, 1) }

        it "computes the same number of elapsed days in the non-leap prior year" do
          window = described_class.for("y0", reference_date: ref)
          # elapsed=60 (Jan+Feb=59, plus Mar 1 → day 61, so ref-boy=60)
          expect(window.prev_end).to eq(Date.new(2023, 1, 1) + (ref - ref.beginning_of_year).to_i)
        end
      end
    end

    context "y1 (last full year)" do
      subject(:window) { described_class.for("y1", reference_date: ref) }

      it { expect(window.start_date).to eq(Date.new(2025, 1, 1)) }
      it { expect(window.end_date).to eq(Date.new(2025, 12, 31)) }
      it { expect(window.prev_start).to eq(Date.new(2024, 1, 1)) }
      it { expect(window.prev_end).to eq(Date.new(2024, 12, 31)) }
      it { expect(window.label).to eq("2025") }
      it { expect(window.comparable?).to be true }
    end
  end

  describe ".cycle" do
    subject(:cycle) { described_class.cycle(reference_date: ref) }

    it "returns one entry per CYCLE token in order" do
      expect(cycle.map { _1[:token] }).to eq(described_class::CYCLE)
    end

    it "includes human labels" do
      labels = cycle.map { _1[:label] }
      expect(labels).to include("7d", "28d", "3m", "1y", "lifetime")
      expect(labels).to include("Jun '26", "May '26", "Apr '26")
      expect(labels).to include("2026", "2025")
    end

    it "returns hashes with exactly :token and :label keys" do
      expect(cycle.first.keys).to contain_exactly(:token, :label)
    end
  end
end
