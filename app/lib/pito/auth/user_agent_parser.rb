# Phase 25 — 01a. UA string → `{browser:, os:}` hash. Thin wrapper
# over the `useragent` gem (already bundled — used by the videos +
# channels surfaces). Pure function, no side effects, deterministic.
#
# The output is intentionally coarse:
#
#   {browser: "Chrome", os: "macOS"}
#
# Neither field includes version numbers. We only need a stable
# label for the attempt-log UI and the notification card; version
# rolling on the underlying browser must not invalidate a trusted
# location (LD-2 keeps version out of the fingerprint).
#
# Empty / unparseable UAs degrade to `{browser: "Unknown", os: "Unknown"}`.
# Common bot UAs (`curl/8.0`) are recognized by the gem and surface
# as their identifier (`curl`) with `os: "Unknown"` — useful for the
# attempt log so the user can spot scripted traffic at a glance.
require "useragent"

module Pito
  module Auth
    module UserAgentParser
      UNKNOWN = "Unknown".freeze

      # The `useragent` gem returns marketing-decorated OS strings
      # (`OS X 10.15.7`, `iOS 17.5.1`, `Linux x86_64`). We strip the
      # decoration so the attempt-log table stays compact and so a
      # rolling OS minor version doesn't multiply trusted-location
      # rows. Pattern is greedy left-anchored: the first match in the
      # OS_PATTERNS list wins.
      OS_PATTERNS = [
        [ /\A(mac\s*os\s*x|os\s*x|macintosh)/i, "macOS" ],
        [ /\A(ipad\s*os)/i,                     "iPadOS" ],
        [ /\A(iphone\s*os|ios)/i,               "iOS" ],
        [ /\A(windows)/i,                       "Windows" ],
        [ /\A(android)/i,                       "Android" ],
        [ /\A(chrome\s*os)/i,                   "ChromeOS" ],
        [ /\A(linux)/i,                         "Linux" ]
      ].freeze

      module_function

      def call(ua_string)
        raw = ua_string.to_s.strip
        return { browser: UNKNOWN, os: UNKNOWN } if raw.empty?

        agent = UserAgent.parse(raw)
        browser_name = agent.browser.to_s
        browser = browser_name.empty? ? UNKNOWN : browser_name

        os_raw = agent.os.to_s
        os = normalize_os(os_raw)

        { browser: browser, os: os }
      rescue StandardError
        { browser: UNKNOWN, os: UNKNOWN }
      end

      def normalize_os(raw)
        return UNKNOWN if raw.to_s.strip.empty?

        OS_PATTERNS.each do |pattern, label|
          return label if pattern.match?(raw)
        end

        # No mapping — return the leading word stripped of version
        # noise so "FreeBSD 14.0" → "FreeBSD" rather than the whole
        # marketing string.
        raw.to_s.split.first || UNKNOWN
      end
    end
  end
end
