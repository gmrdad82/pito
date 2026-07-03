# frozen_string_literal: true

module Pito
  module Capture
    # The Ferrum-backed browser driver for capture scenarios. Wraps exactly the
    # operations Runner's step vocabulary needs — visit / chatbox typing /
    # waits / screenshots — so Runner can be specced against a stub of this
    # interface (CI never launches a browser).
    #
    # Browser binary resolution, in order:
    #   1. ENV["PITO_CAPTURE_BROWSER"] — explicit override
    #   2. the ms-playwright Chrome Headless Shell already on disk (the same
    #      binary the mkt screenshots were shot with)
    #   3. Ferrum's own detection (system chrome/chromium)
    class Browser
      # The pito chatbox input — the seam every `command:`/`login:` step types
      # into (`show game`-style commands are submitted with Enter).
      CHATBOX_SELECTOR = "#pito-chatbox .pito-chatbox__input"

      # Dev-only fixed TOTP (no real secret in development — see the auth docs).
      DEV_LOGIN_COMMAND = "/login 123456"

      def self.headless_shell_path
        Dir.glob(File.expand_path("~/.cache/ms-playwright/chromium_headless_shell-*/chrome-linux*/headless_shell")).max
      end

      def initialize(viewport:)
        @viewport = viewport
      end

      def start
        options = {
          headless:     true,
          timeout:      20,
          window_size:  [ @viewport["width"], @viewport["height"] ],
          browser_options: { "hide-scrollbars" => nil, "force-device-scale-factor" => @viewport["scale"] }
        }
        path = ENV["PITO_CAPTURE_BROWSER"].presence || self.class.headless_shell_path
        options[:browser_path] = path if path.present?
        @ferrum = Ferrum::Browser.new(**options)
      end

      def stop
        @ferrum&.quit
        @ferrum = nil
      end

      def visit(url)
        page.go_to(url)
        page.network.wait_for_idle(timeout: 10)
      rescue Ferrum::TimeoutError
        nil # idle is best-effort; waits are explicit steps
      ensure
        wait_for_fonts
        hide_dev_banner
      end

      # Captures are dev-only, but the shots are for the WORLD — the fixed
      # "DEVELOPMENT" bottom banner must never appear in an artifact (owner
      # 2026-07-03). Injected per page load AND re-verified before every
      # screenshot; a failed hide ABORTS the capture (no silent rescue — the
      # first version swallowed a mid-navigation failure and shipped
      # banner-tainted frames). Capture-only; the app is untouched.
      BANNER_HIDE_CSS = ".pito-dev-banner{display:none!important}"

      def hide_dev_banner
        page.add_style_tag(content: BANNER_HIDE_CSS)
        ensure_banner_hidden!
      end

      def ensure_banner_hidden!(retried: false)
        display = page.evaluate(
          %q[(() => { const b = document.querySelector(".pito-dev-banner"); return b ? getComputedStyle(b).display : "absent"; })()]
        )
        return if %w[none absent].include?(display)
        raise "DEVELOPMENT banner not hidden (display=#{display.inspect})" if retried

        page.add_style_tag(content: BANNER_HIDE_CSS)
        ensure_banner_hidden!(retried: true)
      end

      # RENDER ACCURACY: block until the self-hosted webfont (DejaVu Sans Mono)
      # is actually loaded — a shot fired before `document.fonts.ready` renders
      # the fallback mono and looks subtly wrong (the "not accurate" captures,
      # owner 2026-07-03).
      def wait_for_fonts
        page.evaluate_async("document.fonts.ready.then(() => arguments[0](true))", 5)
      rescue StandardError
        nil
      end

      # Two rAFs — lets the last DOM change actually paint before a shot.
      def settle_paint
        page.evaluate_async(
          "requestAnimationFrame(() => requestAnimationFrame(() => arguments[0](true)))", 2
        )
      rescue StandardError
        nil
      end

      # Type into the chatbox and submit with Enter.
      def submit_command(text)
        input = wait_for_selector(CHATBOX_SELECTOR, timeout: 10)
        input.focus
        input.type(text, :enter)
      end

      # Type WITHOUT submitting — storyboard frames of a half-typed command.
      def type_text(text)
        input = wait_for_selector(CHATBOX_SELECTOR, timeout: 10)
        input.focus
        input.type(text)
      end

      # Submit whatever is typed (the storyboard's `submit: true` step).
      def press_enter
        input = wait_for_selector(CHATBOX_SELECTOR, timeout: 10)
        input.focus
        input.type(:enter)
      end

      def login!
        submit_command(DEV_LOGIN_COMMAND)
        wait_for_selector("#pito-auth-gate[data-authenticated='true']", timeout: 10)
      end

      def wait_for_selector(css, timeout: 10)
        deadline = monotonic + timeout
        loop do
          node = page.at_css(css)
          return node if node

          raise Ferrum::TimeoutError, "selector #{css.inspect} not found in #{timeout}s" if monotonic > deadline

          sleep 0.1
        end
      end

      def wait_for_text(text, timeout: 10)
        deadline = monotonic + timeout
        loop do
          return true if page.body.include?(text)

          raise Ferrum::TimeoutError, "text #{text.inspect} not found in #{timeout}s" if monotonic > deadline

          sleep 0.1
        end
      end

      # PNG capture. `full: true` = the whole page (single shots); false = the
      # viewport only (GIF frames — fixed dimensions, ~5× smaller, what a
      # terminal-showcase GIF should frame). `selector:` clips to one node.
      def screenshot(path, selector: nil, full: true)
        settle_paint
        ensure_banner_hidden!
        if selector
          node = wait_for_selector(selector)
          node.screenshot(path: path.to_s)
        else
          page.screenshot(path: path.to_s, full: full)
        end
      end

      def sleep_for(seconds)
        sleep(seconds.to_f)
      end

      # Scroll a node into view (centered) — storyboards that focus a specific
      # message (the enhanced videos/channels cards, similar games).
      def scroll_to(css)
        wait_for_selector(css)
        page.evaluate(
          "document.querySelector(#{css.to_json})?.scrollIntoView({block: 'center'})"
        )
        settle_paint
      end

      private

      def page
        raise "browser not started" unless @ferrum

        @ferrum.page
      end

      def monotonic
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
