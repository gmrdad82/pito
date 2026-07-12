# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Formatter::Duration, type: :service do
  describe ".call" do
    context "when input is blank or negative" do
      it "returns nil for nil" do
        expect(described_class.call(nil)).to be_nil
      end

      it "returns nil for a negative number" do
        expect(described_class.call(-1)).to be_nil
      end
    end

    context "when duration is exactly zero" do
      it "returns '0:00'" do
        expect(described_class.call(0)).to eq("0:00")
      end
    end

    context "when duration is sub-hour (M:SS, no leading-zero minute)" do
      it "returns '0:05' for 5 seconds (seconds under ten padded)" do
        expect(described_class.call(5)).to eq("0:05")
      end

      it "returns '1:05' for 65 seconds (seconds under ten padded, single-digit minute)" do
        expect(described_class.call(65)).to eq("1:05")
      end

      it "returns '9:34' for 574 seconds" do
        expect(described_class.call(574)).to eq("9:34")
      end

      it "returns '43:23' for 2603 seconds" do
        expect(described_class.call(2603)).to eq("43:23")
      end
    end

    context "when duration is hour-plus (H:MM:SS, padded minutes and seconds)" do
      it "returns '1:02:22' for 3742 seconds" do
        expect(described_class.call(3742)).to eq("1:02:22")
      end

      it "returns '1:00:32' for 3632 seconds (zero minutes, padded)" do
        expect(described_class.call(3632)).to eq("1:00:32")
      end

      it "returns '2:00:00' for 7200 seconds (exact hours)" do
        expect(described_class.call(7200)).to eq("2:00:00")
      end
    end

    context "when duration is day-plus (D:HH:MM:SS, padded inner units)" do
      it "returns '1:02:05:09' for 93909 seconds" do
        expect(described_class.call(93909)).to eq("1:02:05:09")
      end

      it "returns '1:00:00:00' for 86400 seconds (exactly one day)" do
        expect(described_class.call(86400)).to eq("1:00:00:00")
      end

      it "returns '2:00:00:00' for 172800 seconds (exactly two days)" do
        expect(described_class.call(172800)).to eq("2:00:00:00")
      end
    end
  end
end
