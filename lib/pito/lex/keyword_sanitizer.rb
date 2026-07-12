# frozen_string_literal: true

module Pito
  module Lex
    # Downcases command KEYWORD tokens so phone auto-titleization ("List games",
    # "Schedule 22 Tomorrow At 14:30", "sort By views Desc") still matches the
    # case-sensitive tool / connector / time vocabulary.
    #
    # Only `:word` tokens whose downcased value is a KNOWN keyword are lowered —
    # game titles, @handles, numbers, and quoted (`:string`) literals keep their
    # case, so "Demon's Souls" and `"Lies of P"` are never mangled. Idempotent.
    #
    # The set is deliberately scoped to genuine command syntax (tools, nouns,
    # connectors, sort dirs, and the schedule time grammar) — not common English
    # words like "the"/"of"/"and" — to avoid corrupting free-text title args.
    module KeywordSanitizer
      module_function

      KEYWORDS = Set.new(%w[
        list ls show delete rm schedule publish unlist price footage link unlink
        sync import reindex platform find help authenticate connect config disconnect themes
        set unset update snippet add remove sort order slate
        logout notifications notifs exit quit
        share revoke unshare unfold
        with to from by only sorted asc ascending desc descending upcoming
        game games vid vids video videos channel channels sub subs subscriber subscribers
        today tomorrow now next noon midnight night at am pm
        week weeks month months day days hour hours hr hrs minute minutes min mins
        monday tuesday wednesday thursday friday saturday sunday
        mon tue tues wed thu thur thurs fri sat sun
      ]).freeze

      # @param tokens [Array<Pito::Lex::Token>]
      # @return [Array<Pito::Lex::Token>] same stream with keyword :word tokens downcased
      def call(tokens)
        tokens.map do |token|
          next token unless token.type == :word

          down = token.value.to_s.downcase
          next token if down == token.value || !KEYWORDS.include?(down)

          token.with(value: down)
        end
      end
    end
  end
end
