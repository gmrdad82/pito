# Phase 14 §1 — Apicalypse query body builder.
#
# Tiny DSL that emits the IGDB v4 Apicalypse string format:
#   `fields a, b, c; where x = 1 & y > 2; limit 10;`
#
# Numeric IDs are NEVER quoted. String literals embedded via `search`
# are double-quoted; embedded `"` is escaped to `\"`. Multiple
# `where` clauses join with ` & ` (Apicalypse AND).
#
# Pito uses a tiny subset — just enough to build the half-dozen
# request bodies the client emits. No full grammar.
module Igdb
  class Apicalypse
    def initialize
      @fields = []
      @wheres = []
      @search = nil
      @limit  = nil
    end

    def fields(*names)
      raise ArgumentError, "fields requires at least one name" if names.empty?
      @fields.concat(names.map(&:to_s))
      self
    end

    def where(clause)
      raise ArgumentError, "where requires a non-blank clause" if clause.to_s.strip.empty?
      @wheres << clause.to_s
      self
    end

    def limit(n)
      raise ArgumentError, "limit must be a positive integer" unless n.is_a?(Integer) && n.positive?
      @limit = n
      self
    end

    def search(query)
      raise ArgumentError, "search requires a non-blank query" if query.to_s.strip.empty?
      @search = query.to_s
      self
    end

    def to_s
      parts = []
      parts << %(search "#{escape(@search)}";) if @search
      raise ArgumentError, "fields() must be called before to_s" if @fields.empty?
      parts << "fields #{@fields.join(", ")};"
      parts << "where #{@wheres.join(" & ")};" if @wheres.any?
      parts << "limit #{@limit};" if @limit
      parts.join(" ")
    end

    private

    def escape(value)
      value.to_s.gsub('"', '\\"')
    end
  end
end
