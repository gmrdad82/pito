# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Video
      # Builds the payload for the video library list message.
      #
      # Renders a Pito::Video::ListComponent for the matched videos and wraps it
      # with a plain-text intro line. NOT stamped follow-up-able (no video_list
      # follow-up handler exists; consistent with the simplest viable choice).
      #
      # NOTE: The caller is responsible for checking videos.empty? and returning
      # an appropriate empty-state before calling this builder.
      module List
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param videos       [ActiveRecord::Relation | Array<::Video>] non-empty, pre-fetched.
        # @param conversation [Conversation] used for future follow-up stamping (unused now).
        # @return [Hash] string-keyed payload with body and html: true.
        def call(videos, conversation:)
          intro      = Pito::Copy.render("pito.copy.videos.list_intro", { count: videos.size })
          list_html  = render_component(Pito::Video::ListComponent.new(videos:))

          html_payload(body: "#{intro}\n#{list_html}")
        end
      end
    end
  end
end
