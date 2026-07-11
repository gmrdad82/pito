# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builds the CHANNEL-MATCHES recommendations message: two columns —
      # per-game channel DISTRIBUTION (col 1) + channel RECOMMENDATION (col 2),
      # rendered by Pito::Games::ChannelsComponent.
      #
      # PROGRESSIVE: `show game` emits `.pending` INSTANTLY — col 2 (recommendation)
      # rendered directly, col 1 (distribution) as a NoData dotted canvas + a
      # `channel_distribution` marker. The Finalizer enqueues ChannelDistributionFillJob,
      # which computes the shares (Game::ChannelDistribution) and rewrites the message
      # to its ready state (col 1 = offset bars) — mirroring the analyze/glance fill.
      # The intro + captions are chosen ONCE here and stored in the marker so they
      # never change under the user on the swap.
      #
      # Stamped follow-up-able (reply_target: "game_channels") so the user can reply
      # `#<handle> show @<handle>` to drill into a matched channel.
      module Channels
        extend Pito::MessageBuilder::Helpers
        module_function

        # True when a persisted event carries a channel-distribution marker still
        # pending (its async fill hasn't run). Used by the Finalizer gate + the job.
        def pending?(event)
          event.payload.is_a?(Hash) && event.payload.dig("channel_distribution", "status") == "pending"
        end

        # The INSTANT message: col 2 rendered, col 1 NoData, marker pending.
        # @param game         [::Game]
        # @param conversation [Conversation] used to generate the reply handle.
        # @return [Hash] event payload.
        def pending(game, conversation:)
          intro        = Pito::Copy.render_html("pito.copy.games.channels_match_header")
          dist_caption = Pito::Copy.render("pito.copy.games.channel_distribution_caption")
          reco_caption = Pito::Copy.render("pito.copy.games.channel_recommendation_caption")

          body    = ready_body(game: game, intro: intro,
                               distribution_caption: dist_caption,
                               recommendation_caption: reco_caption, shares: nil)
          payload = html_payload(body: body, game_id: game.id, anchor: true)
          payload["channel_distribution"] = {
            "status"                 => "pending",
            "game_id"                => game.id,
            "intro"                  => intro,
            "distribution_caption"   => dist_caption,
            "recommendation_caption" => reco_caption
          }
          Pito::FollowUp.make_followupable!(payload, target: "game_channels", conversation:)
          payload
        end

        # Render the message body (col 1 = bars when `shares` present, else NoData).
        # Shared by `pending` (shares nil) and the fill job (shares present).
        def ready_body(game:, intro:, distribution_caption:, recommendation_caption:, shares:)
          render_component(Pito::Games::ChannelsComponent.new(
            game: game, intro: intro,
            distribution_caption: distribution_caption,
            recommendation_caption: recommendation_caption, shares: shares
          ))
        end
      end
    end
  end
end
