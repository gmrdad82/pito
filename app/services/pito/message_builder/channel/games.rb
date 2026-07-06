# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Channel
      # Builds the `:enhanced` GAMES GRID shown for a channel (G120) — the
      # channel's linked games as similar-games-style cover cards (strip
      # cover, #id + per-channel vid count, no title/score), alphabetical.
      #
      # Streamed by `show channel @handle with games` / `full` (between detail
      # and videos), the `games channel @handle` segment verb, and the `games`
      # reply on channel messages. Stamped follow-up-able
      # (reply_target: "channel_games") so `#<handle> show <id>` drills into a
      # game from the grid.
      #
      # NOTE: caller guards via has_linked_games and skips this for a channel
      # with no linked games (verbs.yml emit_if — mirrors videos).
      # NAMESPACE: `Channel` is the MessageBuilder sub-module; use ::Channel /
      # the passed record for the model.
      module Games
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param channel      [::Channel]    the channel whose games to show.
        # @param conversation [Conversation] used to generate the reply handle.
        # @return [Hash] event payload (body html + html: true + channel_id +
        #   structured games rows, follow-up stamped).
        def call(channel, conversation:)
          component = Pito::Channel::GamesComponent.new(channel: channel)
          body      = render_component(component)
          payload   = html_payload(body: body, channel_id: channel.id)
          # G126: structured rows beside the html — text clients (pito-tui)
          # can't render cover art, so they draw from id/title/vids instead
          # of the body. Same records, same alphabetical order as the grid.
          payload["games"] = component.games.map do |g|
            { "id" => g.id, "title" => g.title, "vids" => g[:channel_vids_count] }
          end
          Pito::FollowUp.make_followupable!(payload, target: "channel_games", conversation:)
          payload
        end
      end
    end
  end
end
