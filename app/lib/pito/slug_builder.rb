# Friendly URLs.
#
# Shared slug normalization used by `friendly_id` model declarations and
# the slug-column backfill migrations. The result mirrors the gem's
# `:slugged` default (lowercase + transliterated + hyphen-separated) plus a
# project-specific `limit` truncation that prefers a hyphen boundary over a
# mid-word cut.
#
# Why a small wrapper rather than calling `friendly_id` directly inside
# the migrations: migrations should not depend on live ActiveRecord
# models (those carry validations / callbacks / has_many cascades that
# can blow up on a schema mid-shift). `SlugBuilder.build` is pure-Ruby
# and uses only `ActiveSupport::Inflector#transliterate` — safe to call
# from a `find_each` block on an anonymous `Class.new(ActiveRecord::Base)`
# table-stub.
#
# The public surface intentionally matches the locked decision in
# `docs/plans/beta/20-friendly-urls/specs/01-friendly-urls-app-wide.md`
# (master-agent decision #6, 2026-05-10): default 80-char cap, configurable
# per call site via the `limit:` kwarg.
module Pito
  module SlugBuilder
    DEFAULT_LIMIT = 80

    module_function

    # Returns a URL-safe slug derived from `input`. Steps:
    #   1. Coerce to string, strip surrounding whitespace.
    #   2. Transliterate (Café → Cafe).
    #   3. Replace any non-[a-z0-9] run with a single `-`.
    #   4. Strip leading / trailing `-`.
    #   5. Truncate at `limit`, preferring a hyphen boundary so the slug
    #      never ends mid-word.
    #
    # Returns "" when the cleanup leaves nothing — callers must supply a
    # fallback (`bundle-#{id}` etc.).
    def build(input, limit: DEFAULT_LIMIT)
      raw = input.to_s.strip
      return "" if raw.empty?

      # ActiveSupport::Inflector.transliterate replaces accented characters
      # with their closest ASCII equivalent. Non-Latin scripts (Cyrillic,
      # CJK) collapse to "?" — strip them so the slug doesn't carry "?"
      # and we fall back to the controller's id-based slug instead.
      ascii = ActiveSupport::Inflector.transliterate(raw, "")

      # Collapse anything that isn't [a-z0-9] (after lowercasing) into "-".
      lowered = ascii.downcase.gsub(/[^a-z0-9]+/, "-")
      trimmed = lowered.gsub(/\A-+|-+\z/, "")
      return "" if trimmed.empty?

      truncate(trimmed, limit)
    end

    # Truncate to `limit` characters, preferring a hyphen boundary in the
    # last quarter of the limit so the slug doesn't end mid-word. When no
    # hyphen exists in that window, fall back to a hard cut (still cleaning
    # any trailing hyphen).
    def truncate(slug, limit)
      return slug if slug.length <= limit

      window_start = (limit * 0.75).to_i
      head = slug[0, limit]
      last_hyphen = head.rindex("-")
      head = head[0, last_hyphen] if last_hyphen && last_hyphen >= window_start
      head.gsub(/-+\z/, "")
    end
  end
end
