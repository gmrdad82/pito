# frozen_string_literal: true

require "open3"

module Pito
  module Footage
    # Runs ffprobe against a video file and returns its duration. Footage stores
    # only filename + duration, so that's all the Probe extracts.
    #
    # Usage:
    #   Pito::Footage::Probe.call(path: "/path/to/clip.mp4")
    #   # => #<Result duration_seconds: 312, success: true, error_message: nil>
    class Probe
      Result = Data.define(:duration_seconds, :success, :error_message)

      class << self
        def call(path:)
          new(path:).call
        end
      end

      def initialize(path:)
        @path = path.to_s
      end

      def call
        unless File.exist?(@path)
          return failure("File not found: #{@path}")
        end

        json = run_ffprobe
        return failure(json) if json.is_a?(String) # error message

        parse(json)
      rescue JSON::ParserError => e
        failure("ffprobe output is not valid JSON: #{e.message}")
      rescue StandardError => e
        failure("Probe failed: #{e.class}: #{e.message}")
      end

      private

      def run_ffprobe
        cmd = [
          "ffprobe", "-v", "quiet",
          "-print_format", "json",
          "-show_streams", "-show_format",
          @path
        ]

        output, status = Open3.capture2(*cmd)
        return "ffprobe failed (exit #{status.exitstatus})" unless status.success?

        JSON.parse(output)
      end

      def parse(data)
        video = data["streams"]&.find { |s| s["codec_type"] == "video" }
        return failure("No video stream found") unless video

        Result.new(
          duration_seconds: infer_duration(data, video),
          success:          true,
          error_message:    nil
        )
      end

      def infer_duration(data, video)
        # Prefer format duration (most reliable), fall back to video stream
        raw = data.dig("format", "duration") || video["duration"]
        return nil if raw.nil?

        raw.to_f.round
      end

      def failure(message)
        Result.new(duration_seconds: nil, success: false, error_message: message)
      end
    end
  end
end
