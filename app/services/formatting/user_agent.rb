# Formatting::UserAgent — minimal regex-driven UA parser for the
# sessions table on `/settings` security pane.
#
# Beta 4 — FB-50 (2026-05-20). Replaced the raw `<code>{user_agent}</code>`
# cell with split `device` + `browser` columns. The full UA string is
# noisy; this service projects it down to a small enumerated set:
#
#   device  -> linux | macos | ios | windows | android | -
#   browser -> firefox | chrome | safari | -
#
# Synthetic test agents (short kebab-case tokens like `smoke`,
# `wave-a2-smoke`, `SmokeAgent`) are passed through verbatim so spec
# fixtures + smoke harnesses still read cleanly in the rendered table.
#
# Detection order matters:
#   * `device`: Android is checked BEFORE Linux because Android UAs
#     contain the substring `Linux`. iOS is checked BEFORE macOS for
#     the same reason — iPad UAs contain `Mac OS X` since iPadOS 13.
#   * `browser`: Firefox first because Chrome UAs contain
#     `AppleWebKit/Safari`, and Chrome before Safari because Chrome
#     UAs also contain `Safari`.
module Formatting
  module UserAgent
    module_function

    DEVICE_FALLBACK = "-".freeze
    BROWSER_FALLBACK = "-".freeze

    SYNTHETIC_AGENT = /\A[a-z][a-z0-9-]*\z/i

    def device(ua_string)
      return DEVICE_FALLBACK if ua_string.blank?
      return ua_string if synthetic?(ua_string)

      case ua_string
      when /Android/i              then "android"
      when /iPhone|iPad|iPod/i     then "ios"
      when /Mac OS X|macOS/i       then "macos"
      when /Windows/i              then "windows"
      when /Linux|X11/i            then "linux"
      else DEVICE_FALLBACK
      end
    end

    def browser(ua_string)
      return BROWSER_FALLBACK if ua_string.blank?
      return ua_string if synthetic?(ua_string)

      case ua_string
      when /Firefox/i              then "firefox"
      when /Edg\//i, /Edge/i       then "edge"
      when /Chrome|Chromium/i      then "chrome"
      when /Safari/i               then "safari"
      else BROWSER_FALLBACK
      end
    end

    def synthetic?(ua_string)
      ua_string.match?(SYNTHETIC_AGENT)
    end
  end
end
