# frozen_string_literal: true

module Pito
  module Event
    module Ai
      # An entity image block inside an :ai message. The model only ever names
      # `entity + id + variant`; the record and its (host-less proxy) URL
      # resolve server-side through the entities' existing variant helpers, and
      # a missing image falls back to the shared click-to-sync placeholder via
      # Pito::ImageRender — identical to the detail cards.
      class MediaBlockComponent < ViewComponent::Base
        WIDTH_CLASS = "block max-w-full"

        def initialize(entity:, id:, variant:)
          @entity  = entity.to_s
          @id      = id.to_i
          @variant = variant.to_s
          @record  = resolve_record
        end

        def render?
          @record.present?
        end

        def call
          tag.div(class: "pito-ai-media") do
            render(Pito::ImageRender.call(
              url:          url,
              shape:        @variant == "avatar" ? :circle : :rect,
              sync_command: sync_command,
              alt:          alt,
              html_class:   WIDTH_CLASS
            ))
          end
        end

        private

        def resolve_record
          case @entity
          when "game"    then ::Game.find_by(id: @id)
          when "vid"     then ::Video.find_by(id: @id)
          when "channel" then ::Channel.find_by(id: @id)
          end
        end

        def url
          case [ @entity, @variant ]
          in [ "game", _ ]         then Pito::ImagePath.call(@record.cover_art, variant: :detail)
          in [ "vid", _ ]          then @record.thumbnail_variant_url
          in [ "channel", "banner" ] then Pito::ImagePath.call(@record.banner, variant: :display)
          else                          @record.avatar_inline_url
          end
        end

        def alt
          @record.respond_to?(:title) ? @record.title : @record.try(:display_name)
        end

        def sync_command
          case @entity
          when "game"    then "sync game ##{@id}"
          when "vid"     then "sync vids"
          when "channel" then "sync channels"
          end
        end
      end
    end
  end
end
