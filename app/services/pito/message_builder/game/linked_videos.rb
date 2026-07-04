# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builds the payload for the LINKED-VIDEOS list shown under a game detail.
      #
      # Streamed right after the game detail on `show game <ref>`. Wraps
      # Video::List so the table is identical to the standalone video library
      # list — id + title plus channel / duration / views / comments / likes
      # columns — then upgrades the follow-up target from "video_list" to
      # "game_linked_videos" and injects `game_id`, enabling two additional
      # context-aware verbs:
      #
      #   #<handle> show <id>      → show vid (free-chat dispatch, no follow_up scope)
      #   #<handle> unlink <id>    → unlink this vid from the implied game
      #
      # The game_id stored in the payload is the "detail context" key that
      # Unlink::follow_up_multi reads to know which game the vid should be
      # unlinked from — no need to specify the game explicitly in the reply.
      #
      # The generic videos list_intro is replaced with a game-scoped dim intro
      # line (pito.copy.game.linked_videos_intro).
      #
      # Rendered as `kind: :enhanced` (the pito chrome). Repliable via the
      # make_followupable! stamp that Video::List applies, overridden to target
      # "game_linked_videos".
      #
      # NOTE: The caller is responsible for checking game.linked_videos.empty?
      # and skipping this builder for a game with no linked videos.
      module LinkedVideos
        module_function

        # Canonical extra columns shown for a game's linked videos.
        # (:comments left with the vids-list comms column — G26.1 removed it
        # from Video::ListColumns, and this card is the same surface family.)
        COLUMNS = %i[channel duration views likes].freeze

        # @param game         [::Game]       the game whose linked videos to list.
        # @param conversation [Conversation] used to generate the reply handle.
        # @return [Hash] string-keyed table_rows payload, follow-up stamped (game_linked_videos).
        def call(game, conversation:)
          videos  = game.linked_videos
          payload = Video::List.call(videos, conversation: conversation, columns: COLUMNS)
          payload["body"] = intro_with_channels(game, videos)
          # The intro now carries a subject-shimmer span (title) and cyan handle
          # tokens, so the body is HTML — flag it so SystemComponent renders it
          # raw (the table rows below stay escaped, driven by their own cells).
          payload["html"]         = true
          # Override the generic video_list target: game_linked_videos adds game
          # context (game_id) for the unlink verb and a show→show vid translation.
          payload["reply_target"] = "game_linked_videos"
          payload["game_id"]      = game.id
          payload
        end

        # The game-scoped intro line (game title in the pito-blue→purple subject
        # shimmer), followed by a witty sentence naming the distinct channels the
        # game appears on as cyan @handle tokens (omitted when there are none).
        # Returns an html_safe String.
        def intro_with_channels(game, videos)
          intro = Pito::Copy.render_html(
            "pito.copy.game.linked_videos_intro",
            { count: videos.size, title: game.title },
            shimmer: [ :title ]
          )

          handles = videos.filter_map { |v| v.channel&.at_handle }.uniq
          return intro if handles.empty?

          channels = Pito::Copy.render_html(
            "pito.copy.game.linked_videos_channels",
            { channels: channel_tokens(handles) }
          )
          ActionController::Base.helpers.safe_join([ intro, channels ], " ")
        end

        # Joins the distinct @handles into a sentence of cyan TokenComponent
        # spans. Each handle's text is escaped inside the span; the connectors are
        # trusted literals, so the result is XSS-safe html.
        def channel_tokens(handles)
          handles.map { |h| Pito::Shimmer::TokenComponent.html(h) }.to_sentence.html_safe
        end
      end
    end
  end
end
