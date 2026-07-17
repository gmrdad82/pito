# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for `search vids` result cards (reply_target: "video_search").
      #
      # A ranking pages exactly like a plain vids list does — `next`/`more`
      # reads the `ranked_ids` cursor Pito::Chat::Handlers::Search#build_video_payload
      # stamps and pages that stored id list in order, via the inherited
      # VideoList#list_next_videos (mirrors Pito::FollowUp::Handlers::GameList's
      # own ranked_ids branch). What still doesn't apply to a ranking: `sort`/
      # `order` (re-sorting would scramble it — a ranking has no independent
      # sort key of its own to re-sort by) and `analyze` (there's no "whole
      # scope" that makes sense to re-analyze on a query-specific result set
      # the way there is for a real list). So VideoSearch supports the pager
      # but still must NOT support sort/order/analyze.
      #
      # It still supports the per-row reply tools (show, delete/rm, publish,
      # unlist, schedule, link, unlink) and column tweaks (with/without),
      # inherited unchanged from VideoList.
      #
      # Availability is config-gated: config/pito/tools.yml declares which
      # actions "video_search" accepts (next/more now included, mirroring
      # game_list's own `next` declaration; sort/order/analyze still NOT
      # declared for it), and `declared?` (from Handler) rejects anything not
      # listed there before this method ever sees it — so the sort/analyze
      # branches are simply absent below, not special-cased out.
      class VideoSearch < VideoList
        self.target "video_search"

        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil)
          action, args = parse_rest(rest)
          return undeclared_action(action) unless declared?(action)

          case action
          when "with", "without"
            mutate_columns(event:, conversation:, action:, args:)
          when "next", "more"
            list_next_videos(event:, conversation:, viewport_width:)
          else
            Pito::FollowUp::ToolDelegator.call(source_event: event, rest:, conversation:, period:, viewport_width:, channel:)
          end
        end
      end
    end
  end
end
