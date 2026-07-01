# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for the LINKED-VIDEOS list shown under a game detail
      # (reply_target: "game_linked_videos").
      #
      # The list is stamped `reply_target: "game_linked_videos"` (overriding the
      # generic "video_list" target) and carries `game_id` in its payload so the
      # unlink verb can identify which game to unlink from without the user
      # spelling it out. The user can reply:
      #
      #   #<handle> show <id>
      #     → Dispatch `show vid #<id>` as free-chat (no follow_up scope) so the
      #       Show handler takes the video branch. Returns the standard video
      #       detail + analytics event set.
      #
      #   #<handle> unlink <id>
      #     → Delegated to Chat::Handlers::Unlink via VerbDelegator. The
      #       source event's `game_id` marks this as a "detail context" for
      #       the Unlink handler's follow_up_multi, so the game is the implied
      #       source and the typed id is the video target. No "from game <id>"
      #       syntax needed from the user. consume: false — the card stays
      #       reusable for subsequent unlinks.
      #
      # Column mutations (no consume, :mutate mode per action):
      #   #<handle> with <columns>     → rebuild list with extra column(s)
      #   #<handle> without <columns>  → rebuild list without the named column(s)
      #
      # Sort mutations (no consume, :mutate mode per action):
      #   #<handle> sort by <col> [desc]  → re-sort the stamped list in place
      #   #<handle> order by <col> [desc] → alias for sort
      #
      # NAMESPACE GOTCHA: Inside Pito::FollowUp::Handlers::*, the bare constant
      # `Game` resolves to the Pito::Game MODULE (not the ActiveRecord model).
      # Always use `::Game` for the model.
      class GameLinkedVideos < Pito::FollowUp::Handler
        self.target "game_linked_videos"
        self.mode   :append
        self.action_modes with: :mutate, without: :mutate, sort: :mutate, order: :mutate
        self.actions "show", "unlink", "with", "without", "sort", "order", "analyze"

        # @param event        [Event]        the game-linked-videos list event.
        # @param rest         [String]       text after `#<handle> `.
        # @param conversation [Conversation] the owning conversation.
        # @return [Result::Append | Result::Mutation | Result::Error]
        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil)
          action, args = parse_rest(rest)

          case action
          when "show"
            # Free-chat dispatch with the "vid" noun so Show takes the video
            # branch — video_target? in follow_up mode reads reply_target, which
            # is "game_linked_videos" (does not start with "video"), so we MUST
            # not pass a follow_up context here.
            result = Pito::Chat::Dispatcher.call(
              input:          "show vid #{args}",
              conversation:   conversation,
              channel:        channel,
              period:         period,
              viewport_width: viewport_width
            )
            Pito::FollowUp::ChatResultAdapter.call(result)
          when "unlink"
            # VerbDelegator with the original source event: reply_target
            # "game_linked_videos" does NOT start with "video", so Unlink's
            # follow_up_unlink sets source_class = ::Game. The presence of
            # game_id in the payload triggers the "detail context" path, making
            # the game the implied source and the typed id the video target.
            Pito::FollowUp::VerbDelegator.call(
              source_event:   event,
              rest:           rest,
              conversation:   conversation,
              period:         period,
              viewport_width: viewport_width,
              channel:        channel
            )
          when "with", "without"
            mutate_columns(event:, conversation:, action:, args:)
          when "sort", "order"
            mutate_sort(event:, conversation:, args:)
          when "analyze"
            Pito::FollowUp::AnalyzeReply.append(
              level: :vid, ids: Array(event.payload["video_ids"]).map(&:to_i),
              conversation:, period:
            )
          else
            Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.game_linked_videos.errors.invalid_action",
              message_args: { action: action }
            )
          end
        end

        private

        # Re-sort the stamped linked-videos list by a column token.
        # Strips an optional leading `by`, parses a trailing direction, and
        # resolves the sort key via Video::ListColumns.sort_key_for.
        def mutate_sort(event:, conversation:, args:)
          payload = event.payload.with_indifferent_access
          game    = resolve_game(payload)
          return game_not_found if game.nil?

          current_cols = Array(payload["list_columns"]).map(&:to_sym)

          tokens = args.to_s.strip.split(/\s+/)
          tokens.shift if tokens.first&.downcase == "by"

          direction = :asc
          if tokens.last&.downcase&.match?(/\A(?:desc|descending)\z/)
            direction = :desc
            tokens.pop
          elsif tokens.last&.downcase&.match?(/\A(?:asc|ascending)\z/)
            tokens.pop
          end

          sort_token = tokens.join(" ")

          ids    = Array(payload["video_ids"])
          videos = ::Video.where(id: ids).sort_by { |v| ids.index(v.id) || ids.size }

          key = Pito::MessageBuilder::Video::ListColumns.sort_key_for(
            sort_token, selected_columns: current_cols
          )
          if key
            videos = videos.sort_by { |v| key.call(v) }
            videos.reverse! if direction == :desc
          end

          new_payload = rebuild_payload(game, videos, conversation:, columns: current_cols)
          new_payload["reply_handle"] = payload["reply_handle"]
          new_payload["reply_target"] = payload["reply_target"]

          Pito::FollowUp::Result::Mutation.new(kind: event.kind.to_sym, payload: new_payload)
        end

        # Parse the comma-separated column list from args, compute the new set
        # (with: union; without: difference), reload the same videos, and rebuild
        # the payload preserving the game-scoped intro, reply handle + target, and
        # game_id so the message stays fully repliable.
        def mutate_columns(event:, conversation:, action:, args:)
          payload = event.payload.with_indifferent_access
          game    = resolve_game(payload)
          return game_not_found if game.nil?

          current_cols = Array(payload["list_columns"]).map(&:to_sym)
          vocab        = Pito::MessageBuilder::Video::ListColumns.vocabulary

          delta_cols = args.split(/\s*,\s*/).filter_map { |t|
            vocab[t.strip.downcase]
          }.uniq

          new_cols =
            case action
            when "with"    then (current_cols | delta_cols)
            when "without" then (current_cols - delta_cols)
            end

          ids    = Array(payload["video_ids"])
          videos = ::Video.where(id: ids).sort_by { |v| ids.index(v.id) || ids.size }

          new_payload = rebuild_payload(game, videos, conversation:, columns: new_cols)
          new_payload["reply_handle"] = payload["reply_handle"]
          new_payload["reply_target"] = payload["reply_target"]

          Pito::FollowUp::Result::Mutation.new(kind: event.kind.to_sym, payload: new_payload)
        end

        # Rebuild the linked-videos payload with a fresh Video::List call, then
        # restore the game-scoped intro + html flag + game_id.  The reply_handle
        # and reply_target are overwritten by the callers to preserve the
        # original handle.
        def rebuild_payload(game, videos, conversation:, columns:)
          payload = Pito::MessageBuilder::Video::List.call(videos, conversation:, columns:)
          payload["body"]    = Pito::MessageBuilder::Game::LinkedVideos.intro_with_channels(game, videos)
          payload["html"]    = true
          payload["game_id"] = game.id
          payload
        end

        # Look up the ::Game from the event payload's game_id.
        def resolve_game(payload)
          game_id = payload["game_id"]
          return nil unless game_id.present?

          ::Game.find_by(id: game_id)
        end

        def game_not_found
          Pito::FollowUp::Result::Error.new(
            message_key:  "pito.follow_up.game_linked_videos.errors.game_not_found",
            message_args: {}
          )
        end
      end
    end
  end
end
