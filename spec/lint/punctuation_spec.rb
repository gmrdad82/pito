require "rails_helper"

# Guard spec for the `## Form hints and captions` rule in docs/design.md:
# every `.form-hint` and `.caption` text ends with a sentence-terminating
# punctuation mark (`.`, `?`, or `!`). Single-word labels, headings, and
# bracketed-link button labels are NOT statements and stay punctuation-free
# — they don't carry these utility classes.
#
# Failure mode: a future template adds
# `<span class="form-hint">paste your key</span>` and ships without a
# trailing period, drifting from the design system. The spec walks every
# ERB template under `app/views/` and `app/components/` and fails with a
# precise file:line list of any hint/caption ending without `.`, `?`, or
# `!`.
#
# The regex is approximate (single-element classed spans on one line) —
# it'll miss multi-line elements and ERB-interpolated text. That's
# acceptable for a lint guard — it catches the common case and the
# static text we control. Add an ALLOWED_FILES allowlist for genuine
# cases that the regex over-flags.
RSpec.describe "punctuation in ERB hints and captions" do
  PUNCTUATION_HINT_PATTERNS = [
    # Match `<tag class="form-hint" ...>TEXT</tag>` on one line.
    /<(\w+)\s+class="form-hint"(?:\s+[^>]*)?>([^<]+)<\/\1>/,
    # Match `<tag class="caption" ...>TEXT</tag>` on one line.
    /<(\w+)\s+class="caption"(?:\s+[^>]*)?>([^<]+)<\/\1>/
  ].freeze

  # Files where every hint/caption is intentionally non-punctuated.
  # Document the rationale alongside each entry. Empty for now —
  # everything in tree carries terminating punctuation today.
  PUNCTUATION_ALLOWED_FILES = [].freeze

  # Per-text filters: the pattern matches but the content is genuinely
  # not a statement (a numeric stat, a timer, a single-word label).
  # Add filters here only when the value is genuinely not a sentence;
  # never to silence a real violation.
  def text_excluded?(text)
    # Pure numeric stats / timers like `(123ms)` — not sentences.
    return true if text.match?(/\A\(\s*<%=.*%>.*ms\)\z/)
    # Whitespace-only after strip (e.g. captions that wrap a child).
    return true if text.strip.empty?

    false
  end

  it "ends every form-hint and caption with sentence-terminating punctuation" do
    erb_files = Dir.glob(Rails.root.join("app/{views,components}/**/*.erb").to_s)
    expect(erb_files).not_to be_empty,
      "expected to find ERB templates under app/views and app/components"

    violations = []

    erb_files.each do |path|
      relative = Pathname.new(path).relative_path_from(Rails.root).to_s
      next if PUNCTUATION_ALLOWED_FILES.include?(relative)
      contents = File.read(path)

      PUNCTUATION_HINT_PATTERNS.each do |pattern|
        contents.scan(pattern) do |captures|
          # captures = [tag_name, inner_text]
          inner = captures[1].to_s.strip
          next if text_excluded?(inner)
          # Strip a trailing closing-paren / quote if the punctuation sits
          # before it (e.g. `something.")` — robust to wrappers).
          tail = inner.gsub(/[)\]"'\s]+\z/, "")
          next if tail.end_with?(".", "?", "!")

          # Find the line number for the precise error message.
          # Rescan on $~ position by locating the inner text in the file.
          idx = contents.index(captures[1])
          lineno = idx ? contents[0, idx].count("\n") + 1 : 0
          violations << "#{relative}:#{lineno}: hint/caption missing trailing period: #{inner.inspect}"
        end
      end
    end

    expect(violations).to be_empty,
      "Found hints/captions without trailing punctuation " \
      "(see docs/design.md `## Form hints and captions`):\n" + violations.join("\n")
  end
end
