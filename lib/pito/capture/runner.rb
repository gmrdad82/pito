# frozen_string_literal: true

require "fileutils"
require "open3"

module Pito
  module Capture
    # Executes one Scenario's steps against a Browser (or any object with the
    # same interface — specs inject a stub) and assembles GIFs from captured
    # frame sequences via ffmpeg.
    #
    # GIF capture = N PNG frames at a fixed cadence (`fps` over `duration`
    # seconds) into a frames/ working dir, then ffmpeg's two-pass
    # palettegen/paletteuse pipeline (crisp terminal colors, small files).
    #
    # GIF assembly runs through lib/support/capture/assemble_gif.py (Pillow) —
    # ffmpeg 8.1's paletteuse aborts with an "Internal bug" on real capture
    # sequences (reproduced), and the ms-playwright bundled ffmpeg cannot read
    # PNG sequences at all. Invoked via Open3 with array args (never string
    # interpolation — house security rule).
    class Runner
      def self.call(scenario, browser: nil, root: Rails.root, io: $stdout)
        new(scenario, browser:, root:, io:).call
      end

      def initialize(scenario, browser: nil, root: Rails.root, io: $stdout)
        @scenario = scenario
        @browser  = browser || Browser.new(viewport: scenario.viewport, user_agent: scenario.user_agent)
        @root     = root
        @io       = io
      end

      # @return [Array<Pathname>] the artifacts written (confined to tmp/captures/<name>/)
      def call
        FileUtils.mkdir_p(out_dir)
        @artifacts = []
        @browser.start
        @browser.visit(@scenario.base_url)
        @scenario.steps.each { |step| run_step(step) }
        @artifacts
      ensure
        @browser.stop
      end

      private

      def out_dir
        @out_dir ||= @scenario.output_dir(root: @root)
      end

      def run_step(step)
        key, value = step.first
        case key.to_s
        when "visit"      then @browser.visit(URI.join(@scenario.base_url, value.to_s).to_s)
        when "login"      then @browser.login! if value
        when "command"    then @browser.submit_command(value.to_s)
        when "type"       then @browser.type_text(value.to_s)
        when "submit"     then @browser.press_enter if value
        when "wait_for"   then wait_step(value)
        when "sleep"      then @browser.sleep_for(value)
        when "shot"       then shot_step(value)
        when "gif"        then gif_step(value)
        when "keyframe"   then keyframe_step(value)
        when "burst"      then burst_step(value)
        when "scroll_to"  then scroll_step(value)
        when "storyboard" then storyboard_step(value)
        when "viewport"   then nil # applied at Browser.new; kept for per-scenario docs
        end
      end

      # scroll_to: ".selector"  — centered (the chart-framing default), or
      # scroll_to: { selector: ".selector", align: start } for edge alignment.
      def scroll_step(value)
        if value.is_a?(Hash)
          value = value.stringify_keys
          @browser.scroll_to(value["selector"].to_s, align: value["align"].to_s)
        else
          @browser.scroll_to(value.to_s)
        end
      end

      def wait_step(value)
        value   = value.stringify_keys
        timeout = (value["timeout"] || 10).to_f
        if value["selector"]
          @browser.wait_for_selector(value["selector"], timeout:)
        elsif value["text"]
          @browser.wait_for_text(value["text"], timeout:)
        end
      end

      def shot_step(value)
        value = value.is_a?(Hash) ? value.stringify_keys : { "name" => value.to_s }
        path  = out_dir.join(value["name"])
        @browser.screenshot(path, selector: value["selector"], full: true)
        record(path)
      end

      # STORYBOARD: a deliberate viewport keyframe, registered
      # in order for the storyboard step — and kept on disk as a playable PNG
      # suite in its own right.
      def keyframe_step(value)
        value = value.is_a?(Hash) ? value.stringify_keys : { "name" => value.to_s }
        path  = out_dir.join(value["name"])
        @browser.screenshot(path, selector: value["selector"], full: false)
        keyframes << path
        record(path)
      end

      # BURST: as many frames as the CDP pipe allows, aiming
      # at `fps` — each shot costs real time (~0.3-0.5s at @2x), so the ACHIEVED
      # rate is measured and reported honestly rather than pretended. All frames
      # register as storyboard keyframes AND stay on disk for the
      # keep-every-Nth optimization pass the owner wants to do by eye.
      def burst_step(value)
        value  = value.stringify_keys
        prefix = value["prefix"]
        count  = (value["frames"] || 10).to_i.clamp(1, 200)
        target = (value["fps"] || 10).to_f.clamp(0.5, 30)
        interval = 1.0 / target

        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        count.times do |i|
          frame_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
          path = out_dir.join(format("%s-%04d.png", prefix, i))
          @browser.screenshot(path, selector: value["selector"], full: false)
          keyframes << path
          budget = interval - (Process.clock_gettime(Process::CLOCK_MONOTONIC) - frame_start)
          @browser.sleep_for(budget) if budget.positive?
        end
        elapsed  = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
        achieved = (count / elapsed).round(1)
        @io.puts(format("  burst %s: %d frames in %.1fs — achieved %.1f fps (target %.0f)",
                        prefix, count, elapsed, achieved, target))
      end

      # Assemble the registered keyframes, in order, into a slow GIF —
      # seconds_per_frame instead of fps (1 frame "ls", 1 frame "ls channels",
      # 1 frame thinking, 1 frame the message).
      def storyboard_step(value)
        value = value.stringify_keys
        raise "storyboard: no keyframes registered before assembly" if keyframes.empty?

        # Playback pacing: `fps:` for fluid playback of burst material, or
        # `seconds_per_frame:` for slow deliberate keyframes.
        spf = if value["fps"]
          1.0 / value["fps"].to_f.clamp(0.5, 30)
        else
          (value["seconds_per_frame"] || 1.5).to_f.clamp(0.2, 10)
        end
        work_dir = out_dir.join("#{File.basename(value['name'], '.gif')}-story")
        FileUtils.mkdir_p(work_dir)
        keyframes.each_with_index do |frame, i|
          FileUtils.cp(frame, work_dir.join(format("frame-%04d.png", i)))
        end

        gif_path = out_dir.join(value["name"])
        assemble_gif(work_dir, gif_path, fps: (1.0 / spf).round(4), width: (value["width"] || GIF_WIDTH).to_i)
        record(gif_path)
      end

      def keyframes
        @keyframes ||= []
      end

      # Frames at a fixed cadence → ffmpeg palette GIF.
      def gif_step(value)
        value    = value.stringify_keys
        name     = value["name"]
        fps      = (value["fps"] || 5).to_i.clamp(1, 15)
        duration = (value["duration"] || 4).to_f
        frames   = (fps * duration).ceil

        frames_dir = out_dir.join("#{File.basename(name, '.gif')}-frames")
        FileUtils.mkdir_p(frames_dir)
        interval = 1.0 / fps

        frames.times do |i|
          @browser.screenshot(frames_dir.join(format("frame-%04d.png", i)), selector: value["selector"], full: false)
          @browser.sleep_for(interval)
        end

        gif_path = out_dir.join(name)
        assemble_gif(frames_dir, gif_path, fps:)
        record(gif_path)
      end

      ASSEMBLER = "lib/support/capture/assemble_gif.py"
      GIF_WIDTH = 1000 # site display width; the @2x source PNGs stay on disk

      def assemble_gif(frames_dir, gif_path, fps:, width: GIF_WIDTH)
        duration_ms = (1000.0 / fps).round
        cmd = [ "python3", @root.join(ASSEMBLER).to_s,
                frames_dir.to_s, gif_path.to_s, duration_ms.to_s, width.to_s ]
        _out, err, status = Open3.capture3(*cmd)
        raise "gif assembly failed: #{err.lines.last(3).join.strip}" unless status.success?
      end

      def record(path)
        @artifacts << path
        @io.puts("  captured #{path.relative_path_from(@root)}")
      end
    end
  end
end
