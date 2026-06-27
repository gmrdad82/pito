# frozen_string_literal: true

module Pito
  module ListPager
    # Bottom sentinel for a keyset-paginated list, driven by the generic
    # `pito--list-pager` Stimulus controller. Domain-agnostic — it knows nothing
    # about what it pages.
    #
    #   next_url present → the controller fetches it when the sentinel scrolls
    #     into view (or on a `pito:list-pager:more` event), showing a shimmer
    #     loader meanwhile. The server response appends the next page's rows and
    #     REPLACES this sentinel with a fresh one (new url, or the end state).
    #   next_url nil → end of list: render the playful, reusable "that's
    #     everything" copy (pito.copy.list_end). With no url the controller stops.
    #
    # The stable id (#pito-list-pager-sentinel) is what the append response's
    # turbo_stream.replace targets. Only one paginated list is ever mounted in
    # the sidebar overlay at a time, so a single id is safe.
    class SentinelComponent < ViewComponent::Base
      SENTINEL_ID = "pito-list-pager-sentinel"

      def initialize(next_url: nil)
        @next_url = next_url.presence
      end

      attr_reader :next_url

      def end?
        next_url.nil?
      end

      def end_copy
        Pito::Copy.render("pito.copy.list_end")
      end
    end
  end
end
