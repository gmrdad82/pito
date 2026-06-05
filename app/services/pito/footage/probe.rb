# frozen_string_literal: true

require "open3"

module Pito
  module Footage
    # Runs ffprobe against a video file and returns a hash of
    # `Footage`-shaped attributes.
    #
    # Usage:
    #   Pito::Footage::Probe.call(path: "/path/to/clip.mp4")
    #   # => { resolution: "3840x2160", fps: 60.0, bit_depth: 10, ... }
    class Probe
      Result = Data.define(
        :resolution, :fps, :bit_depth, :duration_seconds,
        :aspect_ratio, :orientation, :needs_grading,
        :audio_track_names,
        :success, :error_message
      )

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

        audio_streams = data["streams"]&.select { |s| s["codec_type"] == "audio" } || []

        width  = video["width"]
        height = video["height"]

        Result.new(
          resolution:      "#{width}x#{height}",
          fps:             eval_fps(video["r_frame_rate"]),
          bit_depth:       infer_bit_depth(video["pix_fmt"]),
          duration_seconds: infer_duration(data, video),
          aspect_ratio:    video["display_aspect_ratio"] || compute_aspect_ratio(width, height),
          orientation:     infer_orientation(width, height),
          needs_grading:   infer_needs_grading(video),
          audio_track_names: extract_audio_names(audio_streams),
          success:         true,
          error_message:   nil
        )
      end

      def eval_fps(r_frame_rate)
        return nil if r_frame_rate.nil? || r_frame_rate == "0/0"

        num, den = r_frame_rate.split("/").map(&:to_f)
        return nil if den.nil? || den.zero?

        (num / den).round(3)
      end

      def infer_bit_depth(pix_fmt)
        return nil if pix_fmt.nil?

        # yuv420p10le, yuv422p10le, p010le, etc. → 10
        # yuv420p, yuvj420p, nv12, etc. → 8
        # yuv420p12le, yuv444p12le → 12
        case pix_fmt
        when /p10|10le/ then 10
        when /p12|12le/ then 12
        when /p16|16le/ then 16
        else
          8
        end
      end

      def infer_duration(data, video)
        # Prefer format duration (most reliable), fall back to video stream
        raw = data.dig("format", "duration") || video["duration"]
        return nil if raw.nil?

        raw.to_f.round
      end

      def compute_aspect_ratio(width, height)
        return nil if width.nil? || height.nil? || height.zero?

        ratio = width.to_f / height.to_f
        common = {
          1.0 => "1:1",
          1.25 => "5:4",
          1.333 => "4:3",
          1.5 => "3:2",
          1.778 => "16:9",
          1.85 => "1.85:1",
          2.35 => "2.35:1",
          2.39 => "2.39:1",
          2.4 => "2.4:1",
          21.0 / 9.0 => "21:9"
        }

        closest = common.min_by { |k, _| (k - ratio).abs }
        return closest.last if closest && (closest.first - ratio).abs < 0.05

        ratio.round(2).to_s
      end

      def infer_orientation(width, height)
        return nil if width.nil? || height.nil?

        if width > height
          ::Footage::ORIENTATIONS[:landscape]
        elsif height > width
          ::Footage::ORIENTATIONS[:portrait]
        else
          ::Footage::ORIENTATIONS[:square]
        end
      end

      def infer_needs_grading(video)
        space    = video["color_space"]
        transfer = video["color_transfer"]
        primaries = video["color_primaries"]

        # SDR-safe only when everything is bt709 (or smpte170m which is
        # close enough for our purposes).
        return true if space.nil? || transfer.nil? || primaries.nil?

        sdr_space    = space == "bt709"
        sdr_transfer = %w[bt709 smpte170m].include?(transfer)
        sdr_primaries = %w[bt709 smpte170m].include?(primaries)

        !(sdr_space && sdr_transfer && sdr_primaries)
      end

      def extract_audio_names(audio_streams)
        audio_streams.map.with_index do |stream, i|
          tags = stream["tags"] || {}
          title = tags["title"]&.strip
          lang  = tags["language"]&.strip

          if title.present?
            title
          elsif lang.present? && lang != "und"
            lang
          else
            "track #{i + 1}"
          end
        end
      end

      def failure(message)
        Result.new(
          resolution: nil, fps: nil, bit_depth: nil,
          duration_seconds: nil, aspect_ratio: nil,
          orientation: nil, needs_grading: nil,
          audio_track_names: [],
          success: false, error_message: message
        )
      end
    end
  end
end
