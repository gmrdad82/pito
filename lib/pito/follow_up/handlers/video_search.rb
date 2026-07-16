# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for `search vids` result cards (reply_target: "video_search").
      #
      # A similarity ranking is a single page — there is no next page to fetch,
      # no re-sort that wouldn't scramble the ranking, and no "analyze the whole
      # scope" that makes sense for a query-specific result set. So unlike
      # VideoList, this handler must NOT support the pager (`next`/`more`),
      # `sort`/`order`, or `analyze` — those would corrupt or paginate a ranking
      # that only makes sense as the single page it was returned as.
      #
      # It still supports the per-row reply tools (show, delete/rm, publish,
      # unlist, schedule, link, unlink) and column tweaks (with/without),
      # inherited unchanged from VideoList.
      #
      # Availability is config-gated: config/pito/tools.yml declares which
      # actions "video_search" accepts (NOT declaring next/more/sort/order/
      # analyze for it), and `declared?` (from Handler) rejects anything not
      # listed there before this method ever sees it — so the pager/sort/
      # analyze branches are simply absent below, not special-cased out.
      class VideoSearch < VideoList
        self.target "video_search"

        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil)
          action, args = parse_rest(rest)
          return undeclared_action(action) unless declared?(action)

          case action
          when "with", "without"
            mutate_columns(event:, conversation:, action:, args:)
          else
            Pito::FollowUp::ToolDelegator.call(source_event: event, rest:, conversation:, period:, viewport_width:, channel:)
          end
        end
      end
    end
  end
end
