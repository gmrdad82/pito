# frozen_string_literal: true

module Pito
  module Search
    module_function

    # Build a tsquery from raw user input, safe for the @@ operator.
    #
    # Uses PG's plainto_tsquery which strips punctuation, handles escaping,
    # and ANDs terms together.  For advanced queries (quoted phrases, boolean
    # operators) the caller can pass raw tsquery text and skip this helper.
    #
    # Returns an Arel node, safe against SQL injection.
    #
    #   Game.where(Pito::Search.matches(:search_vector, "ocean of"))
    #   # → WHERE search_vector @@ plainto_tsquery('english', 'ocean of')
    def matches(column, query)
      quoted = ActiveRecord::Base.connection.quote(query.to_s.strip)
      Arel.sql("#{column} @@ plainto_tsquery('english', #{quoted})")
    end
  end
end
