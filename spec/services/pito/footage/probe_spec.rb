# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Footage::Probe do
  describe ".call" do
    context "with an SDR BT.709 file" do
      let(:sdr_json) { file_fixture("ffprobe/sdr_1440p.json").read }

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/fake/tekken.mkv").and_return(true)
        allow(Open3).to receive(:capture2) { |*_args| [ sdr_json, instance_double(Process::Status, success?: true) ] }
      end

      it "returns a successful result" do
        result = described_class.call(path: "/fake/tekken.mkv")
        expect(result.success).to be true
      end

      it "reads resolution" do
        result = described_class.call(path: "/fake/tekken.mkv")
        expect(result.resolution).to eq("2560x1440")
      end

      it "evaluates 60 fps from r_frame_rate" do
        result = described_class.call(path: "/fake/tekken.mkv")
        expect(result.fps).to eq(60.0)
      end

      it "infers 8-bit from pix_fmt" do
        result = described_class.call(path: "/fake/tekken.mkv")
        expect(result.bit_depth).to eq(8)
      end

      it "rounds duration to seconds" do
        result = described_class.call(path: "/fake/tekken.mkv")
        expect(result.duration_seconds).to eq(414)
      end

      it "sets needs_grading to false for BT.709" do
        result = described_class.call(path: "/fake/tekken.mkv")
        expect(result.needs_grading).to be false
      end

      it "extracts audio track names from tags.title" do
        result = described_class.call(path: "/fake/tekken.mkv")
        expect(result.audio_track_names).to eq(%w[Gameplay Commentary])
      end
    end

    context "with an HDR 10-bit file" do
      let(:hdr_json) { file_fixture("ffprobe/hdr_4k.json").read }

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/fake/lake.mp4").and_return(true)
        allow(Open3).to receive(:capture2) { |*_args| [ hdr_json, instance_double(Process::Status, success?: true) ] }
      end

      it "infers 10-bit from pix_fmt" do
        result = described_class.call(path: "/fake/lake.mp4")
        expect(result.bit_depth).to eq(10)
      end

      it "sets needs_grading to true for HDR" do
        result = described_class.call(path: "/fake/lake.mp4")
        expect(result.needs_grading).to be true
      end

      it "returns 4K resolution" do
        result = described_class.call(path: "/fake/lake.mp4")
        expect(result.resolution).to eq("3840x2160")
      end
    end

    context "various frame rates" do
      {
        "sdr_24fps.json"    => 24.0,
        "sdr_30fps.json"    => 30.0,
        "sdr_29_97fps.json" => 29.97,
        "sdr_23_976fps.json" => 23.976
      }.each do |fixture_name, expected_fps|
        it "evaluates #{expected_fps} fps from #{fixture_name}" do
          json = file_fixture("ffprobe/#{fixture_name}").read
          allow(File).to receive(:exist?).and_call_original
          allow(File).to receive(:exist?).with("/fake/clip.mkv").and_return(true)
          allow(Open3).to receive(:capture2) { |*_args| [ json, instance_double(Process::Status, success?: true) ] }

          result = described_class.call(path: "/fake/clip.mkv")
          expect(result.fps).to eq(expected_fps)
        end
      end
    end

    context "with a portrait 4K vertical video" do
      let(:portrait_json) { file_fixture("ffprobe/portrait_4k.json").read }

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/fake/vertical.mp4").and_return(true)
        allow(Open3).to receive(:capture2) { |*_args| [ portrait_json, instance_double(Process::Status, success?: true) ] }
      end

      it "returns portrait orientation" do
        result = described_class.call(path: "/fake/vertical.mp4")
        expect(result.orientation).to eq("portrait")
      end

      it "reads 4K vertical resolution" do
        result = described_class.call(path: "/fake/vertical.mp4")
        expect(result.resolution).to eq("2160x3840")
      end

      it "computes 9:16 aspect ratio" do
        result = described_class.call(path: "/fake/vertical.mp4")
        expect(result.aspect_ratio).to eq("9:16")
      end
    end

    context "with a 1080p vertical video" do
      let(:vertical_json) { file_fixture("ffprobe/sdr_1080p_vertical.json").read }

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/fake/1080vert.mp4").and_return(true)
        allow(Open3).to receive(:capture2) { |*_args| [ vertical_json, instance_double(Process::Status, success?: true) ] }
      end

      it "returns portrait orientation" do
        result = described_class.call(path: "/fake/1080vert.mp4")
        expect(result.orientation).to eq("portrait")
      end

      it "reads 1080x1920 resolution" do
        result = described_class.call(path: "/fake/1080vert.mp4")
        expect(result.resolution).to eq("1080x1920")
      end
    end

    context "with a square video" do
      let(:square_json) { file_fixture("ffprobe/sdr_1080p_square.json").read }

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/fake/square.mp4").and_return(true)
        allow(Open3).to receive(:capture2) { |*_args| [ square_json, instance_double(Process::Status, success?: true) ] }
      end

      it "returns square orientation" do
        result = described_class.call(path: "/fake/square.mp4")
        expect(result.orientation).to eq("square")
      end

      it "reads 1080x1080 resolution" do
        result = described_class.call(path: "/fake/square.mp4")
        expect(result.resolution).to eq("1080x1080")
      end

      it "computes 1:1 aspect ratio" do
        result = described_class.call(path: "/fake/square.mp4")
        expect(result.aspect_ratio).to eq("1:1")
      end
    end

    context "with no audio streams" do
      let(:no_audio_json) { file_fixture("ffprobe/no_audio.json").read }

      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/fake/silent.mp4").and_return(true)
        allow(Open3).to receive(:capture2) { |*_args| [ no_audio_json, instance_double(Process::Status, success?: true) ] }
      end

      it "returns empty audio_track_names" do
        result = described_class.call(path: "/fake/silent.mp4")
        expect(result.audio_track_names).to eq([])
      end
    end

    context "when the file does not exist" do
      it "returns a failure" do
        result = described_class.call(path: "/nonexistent.mp4")
        expect(result.success).to be false
        expect(result.error_message).to include("File not found")
      end
    end

    context "when ffprobe returns non-zero" do
      before do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with("/fake/broken.mp4").and_return(true)
        allow(Open3).to receive(:capture2) { |*_args| [ "", instance_double(Process::Status, success?: false, exitstatus: 1) ] }
      end

      it "returns a failure" do
        result = described_class.call(path: "/fake/broken.mp4")
        expect(result.success).to be false
        expect(result.error_message).to include("ffprobe failed")
      end
    end
  end
end
