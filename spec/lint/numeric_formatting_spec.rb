require "rails_helper"

# Guard spec for the `## Numbers` rule in docs/design.md:
# all user-visible numeric values render through `number_with_delimiter`,
# producing comma-separated thousands and dot-decimals.
#
# Failure mode: a future template adds `<%= foo.size %>` or `<%= @x_count %>`
# without `number_with_delimiter`, and a value over 999 renders without
# the comma. The spec walks every ERB template under `app/views/` and
# `app/components/` and fails with a precise file:line list of any raw
# numeric render the patterns catch.
#
# To allow a genuine raw render (a value provably bounded by a small
# constant where the formatter would add no value), add the file path
# to ALLOWED_FILES with a comment explaining why. Don't weaken the
# regex itself — the patterns must keep catching new violations.
RSpec.describe "numeric formatting in ERB templates" do
  RAW_NUMERIC_PATTERNS = [
    # `<%= foo.count %>` / `.size` / `.length` (with optional method chain).
    /<%=\s*[@\w.\[\]]+\.(?:count|size|length)\s*%>/,
    # `<%= @something_count %>` (controller-set integer counters).
    /<%=\s*@\w*_count\s*%>/,
    # `<%= foo.total_views %>` (aggregated stats).
    /<%=\s*[@\w.\[\]]+\.total_\w+\s*%>/,
    # `<%= foo.views %>` / `.likes` / `.comments` / `.subscribers` (per-record stats).
    /<%=\s*[@\w.\[\]]+\.(?:views|likes|comments|subscribers)\s*%>/,
    # `<%= @hash[:total] %>` / `[:count]` etc — search results, aggregate buckets.
    /<%=\s*[@\w.]+\[:(?:total|count|size|length|took_ms)\]\s*%>/
  ].freeze

  # Files where every numeric render in the file is intentionally raw.
  # Document the rationale alongside each entry. Empty for now — every
  # current case is either formatted via number_with_delimiter or filtered
  # by the per-line guards below (data-attribute, pluralization helpers).
  ALLOWED_FILES = [].freeze

  # Per-line filters: the pattern itself matches, but the surrounding context
  # makes the raw render correct. Add new filters here only when the value
  # is genuinely not user-visible; never to silence a real violation.
  def line_excluded?(line)
    # Stimulus / HTMX data attribute values. The integer is JS state, not
    # rendered text — formatting it would break the JS reading it.
    return true if line.match?(/\bdata-[\w-]*="[^"]*<%=\s*[@\w.\[\]]+\.(?:count|size|length)\s*%>/)
    return true if line.match?(/\bdata-[\w-]*="[^"]*<%=\s*@\w*_count\s*%>/)
    # Pluralization-suffix helpers: `'s' if items.length != 1` is a string,
    # not a number render. Catches the `if`-style helper anywhere on the line.
    return true if line.match?(/\.(?:length|size|count)\s*[!=]=\s*1/)

    false
  end

  it "renders all user-visible numeric values via number_with_delimiter" do
    erb_files = Dir.glob(Rails.root.join("app/{views,components}/**/*.erb").to_s)
    expect(erb_files).not_to be_empty, "expected to find ERB templates under app/views and app/components"

    violations = []

    erb_files.each do |path|
      relative = Pathname.new(path).relative_path_from(Rails.root).to_s
      next if ALLOWED_FILES.include?(relative)

      File.foreach(path).with_index(1) do |line, lineno|
        next if line_excluded?(line)

        RAW_NUMERIC_PATTERNS.each do |pattern|
          next unless line.match?(pattern)
          violations << "#{relative}:#{lineno}: #{line.strip}"
          break # one violation per line is enough
        end
      end
    end

    expect(violations).to be_empty,
      "Found raw numeric renders that should use `number_with_delimiter` " \
      "(see docs/design.md `## Numbers`):\n" + violations.join("\n")
  end

  # Companion guard for Chartkick charts. Every chart call must pass
  # `thousands: ","` so axis labels and tooltips render with the same
  # comma-separator convention as the rest of the app. See docs/design.md
  # `## Numbers` → "Charts" subsection.
  CHART_HELPERS = %w[bar_chart line_chart column_chart area_chart pie_chart].freeze

  it "passes `thousands:` on every Chartkick chart call" do
    erb_files = Dir.glob(Rails.root.join("app/{views,components}/**/*.erb").to_s)
    violations = []

    erb_files.each do |path|
      relative = Pathname.new(path).relative_path_from(Rails.root).to_s
      contents = File.read(path)

      # Match a chart call, capturing through the closing `%>` of that ERB tag.
      # The regex spans newlines because chart calls often wrap across lines.
      CHART_HELPERS.each do |helper|
        contents.scan(/<%=\s*#{helper}\b[^%]*?%>/m) do |match|
          next if match.include?("thousands:")
          # Locate line number of the match for a precise error.
          lineno = contents[0, contents.index(match)].count("\n") + 1
          violations << "#{relative}:#{lineno}: #{helper} call without `thousands:` option"
        end
      end
    end

    expect(violations).to be_empty,
      "Found Chartkick chart calls without `thousands: \",\"` " \
      "(see docs/design.md `## Numbers` → Charts):\n" + violations.join("\n")
  end
end
