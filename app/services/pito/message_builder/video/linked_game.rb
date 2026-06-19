# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Video
      # Builds the payload for the SLIM linked-game CARD shown under a video
      # detail on `show video <ref>`.
      #
      # Streamed right after the video detail (and before the Video::Enhanced
      # stats placeholder) as `kind: :enhanced`. Prepends a witty intro line
      # (pito.copy.videos.linked_game_intro, interpolating the game title) above
      # Pito::Video::LinkedGameCardComponent for `video.linked_games.first`,
      # stamps `game_id` in the payload, and is made follow-up-able with the
      # `game_detail` target — so the user can reply `#<handle> show` / `reindex`
      # and have those actions apply to the linked GAME (not the video).
      #
      # NOTE: The caller is responsible for checking `video.linked_games.first`
      # and skipping this builder for a video with no linked game.
      module LinkedGame
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param video        [::Video]       the video whose linked game to card.
        # @param conversation [Conversation]  used to generate the reply handle.
        # @return [Hash] enhanced event payload (html body), follow-up stamped (game_detail).
        def call(video, conversation:)
          game = video.linked_games.first
          return nil if game.nil?

          intro_text = Pito::Copy.render("pito.copy.videos.linked_game_intro", { game: game.title })
          intro_html = %(<p class="pito-video-linked-game-intro text-fg-dim mb-2">#{ERB::Util.html_escape(intro_text)}</p>)
          card       = render_component(Pito::Video::LinkedGameCardComponent.new(game: game))
          body       = "#{intro_html}#{card}"

          payload = html_payload(body: body, game_id: game.id)

          Pito::FollowUp.make_followupable!(payload, target: "game_detail", conversation: conversation)

          payload
        end
      end
    end
  end
end
