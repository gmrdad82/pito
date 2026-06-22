# frozen_string_literal: true

module Pito
  module MessageBuilder
    # Builds the payload for a shinies detail message.
    #
    # Renders a per-metric view — one MetricRowComponent per metric in
    # Evaluate.metrics_for(entity) — wrapped in a ShiniesComponent with a
    # 50-variant intro line.  Returns a follow-up-able :system event payload
    # (reply_target: "shinies_detail").
    #
    # Usage:
    #   Pito::MessageBuilder::Shinies.call(game, conversation: conv)
    #   Pito::MessageBuilder::Shinies.call(video, conversation: conv)
    #   Pito::MessageBuilder::Shinies.call(channel, conversation: conv)
    module Shinies
      extend Pito::MessageBuilder::Helpers
      module_function

      def call(entity, conversation:)
        intro = Pito::Copy.render_html("pito.copy.shinies.intro", { name: entity.title }, shimmer: [ :name ])
        body  = render_component(
          Pito::Achievement::ShiniesComponent.new(entity:, intro:)
        )
        id_fields = entity_id_fields(entity)
        payload   = html_payload(body:, **id_fields)
        Pito::FollowUp.make_followupable!(payload, target: "shinies_detail", conversation:)
        payload
      end

      def entity_id_fields(entity)
        case entity
        when ::Channel then { channel_id: entity.id }
        when ::Video   then { video_id:   entity.id }
        when ::Game    then { game_id:    entity.id }
        else {}
        end
      end
    end
  end
end
