# frozen_string_literal: true

module Pito
  module MessageBuilder
    # Builds the payload for a shinies detail message.
    #
    # Renders a per-metric view — one MetricRowComponent per metric in
    # Evaluate.metrics_for(entity) — wrapped in a ShiniesComponent with a
    # 50-variant intro line.  Returns a plain :system event payload with no
    # reply handle (shinies messages are read-only; there is no follow-up
    # handler that consumes them).
    #
    # Usage:
    #   Pito::MessageBuilder::Shinies.call(game)
    #   Pito::MessageBuilder::Shinies.call(video)
    #   Pito::MessageBuilder::Shinies.call(channel)
    module Shinies
      extend Pito::MessageBuilder::Helpers
      module_function

      def call(entity)
        intro = Pito::Copy.render_html("pito.copy.shinies.intro", { name: entity.title }, shimmer: [ :name ])
        body  = render_component(
          Pito::Achievement::ShiniesComponent.new(entity:, intro:)
        )
        id_fields = entity_id_fields(entity)
        html_payload(body:, **id_fields)
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
