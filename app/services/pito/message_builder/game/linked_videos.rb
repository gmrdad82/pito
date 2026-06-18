# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builds the payload for the LINKED-VIDEOS list shown under a game detail.
      #
      # Streamed right after the game detail on `show game <ref>`. Wraps
      # Video::List so the table is identical to the standalone video library
      # list — id + title plus channel / duration / views / comments / likes
      # columns — and inherits its `video_list` follow-up target, so the user can
      # reply `#<handle> show <id>`, sort, add columns, etc.
      #
      # The generic videos list_intro is replaced with a game-scoped dim intro
      # line (pito.copy.game.linked_videos_intro).
      #
      # Rendered as `kind: :enhanced` (the pito chrome). Repliable via the
      # make_followupable! stamp that Video::List already applies (target:
      # "video_list").
      #
      # NOTE: The caller is responsible for checking game.linked_videos.empty?
      # and skipping this builder for a game with no linked videos.
      module LinkedVideos
        module_function

        # Canonical extra columns shown for a game's linked videos.
        COLUMNS = %i[channel duration views comments likes].freeze

        # @param game         [::Game]       the game whose linked videos to list.
        # @param conversation [Conversation] used to generate the reply handle.
        # @return [Hash] string-keyed table_rows payload, follow-up stamped (video_list).
        def call(game, conversation:)
          videos  = game.linked_videos
          payload = Video::List.call(videos, conversation: conversation, columns: COLUMNS)
          payload["body"] = Pito::Copy.render(
            "pito.copy.game.linked_videos_intro",
            count: videos.size, title: game.title
          )
          payload
        end
      end
    end
  end
end
