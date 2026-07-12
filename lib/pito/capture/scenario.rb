# frozen_string_literal: true

module Pito
  module Capture
    # One capture SCENARIO — a YAML instruction file under config/captures/
    # describing what to show and what to record (the committed successor to
    # the throwaway heredocs that shot the mkt images).
    #
    #   name: ls-channels
    #   base_url: http://localhost:3027   # pito dev; a pitomd preview works too
    #   viewport: { width: 1000, height: 900, scale: 2 }   # scale 2 = retina @2x
    #   steps:
    #     - login: true                    # dev-only fixed TOTP (/login 123456)
    #     - command: "ls channels"         # type into the chatbox + Enter
    #     - wait_for: { text: "channels await", timeout: 10 }
    #     - sleep: 0.4
    #     - shot: ls-channels.png          # single PNG
    #     - gif: { name: ls-channels.gif, duration: 4, fps: 5 }
    #
    # STORYBOARD mode — deliberate keyframes instead of
    # time-sampled frames: register a `keyframe:` shot at each staged moment
    # (half-typed command / thinking block / rendered message), then a
    # `storyboard:` step assembles the registered frames, in order, into a
    # slow GIF (seconds_per_frame). The keyframe PNGs stay on disk as a
    # playable suite either way:
    #
    #     - type: "ls"
    #     - keyframe: 01-ls.png
    #     - type: " channels"
    #     - keyframe: 02-ls-channels.png
    #     - submit: true
    #     - keyframe: 03-thinking.png
    #     - wait_for: { text: "channels", timeout: 15 }
    #     - keyframe: 04-message.png
    #     - storyboard: { name: ls-channels.gif, seconds_per_frame: 1.6 }
    #
    # Step vocabulary: visit / login / command / wait_for (selector: or text:) /
    # sleep / shot / gif / viewport. Unknown steps fail validation loudly.
    #
    # OUTPUT CONFINEMENT: everything lands under tmp/captures/<name>/ — the
    # tool never writes into docs/media/ or a website's asset tree, so existing
    # shipped images can never be overwritten. Promoting a capture is a
    # deliberate manual copy.
    class Scenario
      STEP_KEYS = %w[visit login command type submit wait_for sleep shot gif keyframe burst scroll_to storyboard viewport].freeze

      DEFAULT_VIEWPORT = { "width" => 1000, "height" => 900, "scale" => 2 }.freeze

      class InvalidScenario < StandardError; end

      attr_reader :name, :base_url, :viewport, :steps, :path, :scope

      def self.load(path, scope: nil)
        raw = YAML.safe_load_file(path, aliases: false)
        raise InvalidScenario, "#{path}: not a mapping" unless raw.is_a?(Hash)

        new(raw, path:, scope:)
      end

      # pito's own scenarios (rake pito:capture).
      def self.all(dir: Rails.root.join("config/captures"))
        Dir.glob(dir.join("*.yml")).sort.map { |p| load(p) }
      end

      # The pitomd-destined set (rake pitomd:capture) — stored apart in
      # lib/support/pitomd and output-scoped so the two sets can never collide.
      def self.pitomd(dir: Rails.root.join("lib/support/pitomd"))
        Dir.glob(dir.join("*.yml")).sort.map { |p| load(p, scope: "pitomd") }
      end

      def initialize(raw, path: nil, scope: nil)
        @path     = path
        @scope    = scope.presence
        @name     = raw["name"].to_s
        @base_url = raw["base_url"].to_s
        @viewport = DEFAULT_VIEWPORT.merge(raw["viewport"] || {})
        @steps    = Array(raw["steps"])
        validate!
      end

      # The confined output directory for this scenario's artifacts —
      # tmp/captures/<scope>/<name> when scoped (pitomd), tmp/captures/<name>
      # otherwise. Always under tmp/captures either way.
      def output_dir(root: Rails.root)
        root.join(*[ "tmp/captures", scope, name ].compact)
      end

      private

      def validate!
        raise InvalidScenario, "#{where}: `name` is required" if name.blank?
        raise InvalidScenario, "#{where}: `name` must be filesystem-safe" unless name.match?(/\A[a-z0-9][a-z0-9_-]*\z/)
        raise InvalidScenario, "#{where}: `base_url` is required" if base_url.blank?
        raise InvalidScenario, "#{where}: `steps` must be a non-empty list" if steps.empty?

        steps.each_with_index do |step, i|
          raise InvalidScenario, "#{where}: step #{i + 1} must be a single-key mapping" unless step.is_a?(Hash) && step.size == 1

          key = step.keys.first.to_s
          raise InvalidScenario, "#{where}: step #{i + 1} `#{key}` is not a known step (#{STEP_KEYS.join('/')})" unless STEP_KEYS.include?(key)

          validate_output_name!(i, step) if %w[shot gif keyframe storyboard].include?(key)
          validate_prefix!(i, step) if key == "burst"
        end
      end

      # shot/gif names must be bare filenames — no traversal out of the
      # confined tmp/captures/<name>/ directory.
      def validate_output_name!(index, step)
        key   = step.keys.first
        value = step[key]
        fname = value.is_a?(Hash) ? value["name"].to_s : value.to_s
        return if fname.match?(/\A[a-z0-9][a-z0-9_.-]*\.(png|gif)\z/i) && !fname.include?("/")

        raise InvalidScenario, "#{where}: step #{index + 1} `#{key}` needs a bare .png/.gif filename (got #{fname.inspect})"
      end

      # burst uses a name PREFIX (frames are numbered) — same bare-name rule.
      def validate_prefix!(index, step)
        prefix = step["burst"].is_a?(Hash) ? step["burst"]["prefix"].to_s : ""
        return if prefix.match?(/\A[a-z0-9][a-z0-9_-]*\z/i)

        raise InvalidScenario, "#{where}: step #{index + 1} `burst` needs a bare `prefix` (got #{prefix.inspect})"
      end

      def where
        path || "scenario `#{name.presence || '?'}`"
      end
    end
  end
end
