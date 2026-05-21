# Pure function. Server-side fixed-length middle truncation.
#
# Returns a single string with a Unicode ellipsis (U+2026) joining the
# leading `head` chars and the trailing `tail` chars. The input is
# returned as-is when it is short enough that truncation would not
# actually shorten it (i.e. length <= head + 1 + tail).
#
# Used by the /channels and /videos index URL cells to keep the
# YouTube channel ID visible while collapsing the boilerplate prefix.
# Also used by the footage filename column (via FootageHelper).
#
# Examples:
#   call("", head: 8, tail: 8)                      => ""
#   call("short", head: 8, tail: 8)                 => "short"
#   call("https://example.com/UCxxxxxxxxxxxxxx", head: 8, tail: 6)
#     => "https://…xxxxxx"
#
# Pure function — no I/O, no Rails dependency.
module Pito
  module Formatter
    module MiddleTruncate
      ELLIPSIS = "…".freeze

      module_function

      def call(str, head:, tail:)
        s = str.to_s
        return "" if s.empty?
        return s if s.length <= head + 1 + tail

        "#{s[0...head]}#{ELLIPSIS}#{s[-tail..]}"
      end
    end
  end
end
