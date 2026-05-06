# Markdown-aware word counting for notes. Lives in a dedicated helper
# so the model stays storage-only (`Note` is a thin wrapper around the
# on-disk markdown file plus a few cached counts).
#
# Strategy: render markdown to HTML via Commonmarker (matching the SSR
# helper `ApplicationHelper#render_markdown`), strip the tags to plain
# text, then tokenize with `\p{Word}+` (Unicode word characters).
# Headings, lists, code fences, links, emphasis, blockquotes are all
# handled by Commonmarker — their syntax characters never reach the
# tokenizer. Code-fence content DOES contribute (the text inside the
# fence renders as plain text inside `<pre><code>`), so `` ```\nfoo\n``` ``
# counts as 1 word.
#
# Used by `Note#recompute_counts` (assigned via `body_for_counts`
# before save) and by the live-counter status bar in the editor's
# Stimulus controller through SSR-equivalence.
module NoteHelper
  module_function

  def word_count(body)
    text = body.to_s
    return 0 if text.strip.empty?

    html = Commonmarker.to_html(text, options: { render: { hardbreaks: true } })
    plain = ActionController::Base.helpers.strip_tags(html)
    plain.scan(/\p{Word}+/).size
  end

  # Renders a word count as the compact `Nw` label used by the projects
  # index notes column — `6` becomes `"6w"`, `12232` becomes `"12,232w"`
  # (comma thousand separators via Rails' `number_with_delimiter`).
  #
  # Returns the em-dash placeholder for nil / zero, mirroring the
  # convention used by `FootageHelper#human_filesize` and
  # `human_duration` for "not yet probed / no value" cells. We
  # intentionally don't reference `FootageHelper::EMPTY_VALUE` here —
  # the two helpers stay independent — but the glyph matches.
  def human_words(count)
    return "—" if count.nil? || count.zero?
    "#{ActionController::Base.helpers.number_with_delimiter(count)}w"
  end
end
