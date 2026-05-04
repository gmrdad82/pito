# Phase 4 §6.5 — ATX H1 only, fallback "Untitled note".
#
# Single-rule parser:
#   - Strip leading blank lines.
#   - If the first non-blank line begins with `# ` (single hash + single
#     space), the rest of that line is the title. Truncate to TITLE_MAX_LENGTH.
#   - Otherwise the title is "Untitled note".
#
# DELIBERATELY DROPPED (treated as plain content): Setext headings,
# Textile/RDoc/org-mode headings, YAML frontmatter, HTML <h1>.
module NoteTitleParser
  FALLBACK_TITLE = "Untitled note"

  module_function

  def parse(body)
    return FALLBACK_TITLE if body.nil?

    body.to_s.each_line do |line|
      stripped = line.rstrip
      next if stripped.empty? # skip leading blank lines

      if stripped.start_with?("# ") && !stripped.start_with?("## ")
        title = stripped[2..].to_s.strip
        return FALLBACK_TITLE if title.empty?
        return title[0, Note::TITLE_MAX_LENGTH]
      end

      return FALLBACK_TITLE
    end

    FALLBACK_TITLE
  end
end
