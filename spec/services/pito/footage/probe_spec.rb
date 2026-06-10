# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Footage::Probe do
  describe ".call" do
    context "with a valid video file" do
      let(:sdr_json) { file_fixture("ffprobe/sdr_1440p.json").read }

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/fake/tekken.mkv").and_return(true)
        allow(Open3).to receive(:capture2) { |*_args| [ sdr_json, instance_double(Process::Status, success?: true) ] }
      end

      it "returns success: true" do
        result = described_class.call(path: "/fake/tekken.mkv")
        expect(result.success).to be true
      end

      it "returns the rounded duration in seconds" do
        result = described_class.call(path: "/fake/tekken.mkv")
        expect(result.duration_seconds).to eq(414)
      end
    end

    context "when the file does not exist" do
      it "returns success: false with a File not found error_message" do
        result = described_class.call(path: "/nonexistent.mp4")
        expect(result.success).to be false
        expect(result.error_message).to include("File not found")
      end
    end

    context "when ffprobe exits with a non-zero status" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/fake/broken.mp4").and_return(true)
        allow(Open3).to receive(:capture2) { |*_args| [ "", instance_double(Process::Status, success?: false, exitstatus: 1) ] }
      end

      it "returns success: false with an ffprobe failed error_message" do
        result = described_class.call(path: "/fake/broken.mp4")
        expect(result.success).to be false
        expect(result.error_message).to include("ffprobe failed")
      end
    end

    context "when there is no video stream" do
      let(:audio_only_json) do
        JSON.generate({
          "streams" => [ { "index" => 0, "codec_type" => "audio", "codec_name" => "aac" } ],
          "format"  => { "duration" => "120.0" }
        })
      end

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/fake/audio_only.mp4").and_return(true)
        allow(Open3).to receive(:capture2) { |*_args| [ audio_only_json, instance_double(Process::Status, success?: true) ] }
      end

      it "returns success: false with a No video stream error_message" do
        result = described_class.call(path: "/fake/audio_only.mp4")
        expect(result.success).to be false
        expect(result.error_message).to include("No video stream found")
      end
    end
  end
end
