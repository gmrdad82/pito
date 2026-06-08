# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Video
      # Builds the payload for the video library list message.
      #
      # Returns a table_rows payload (kv-table via SystemComponent) with a
      # 4-column cells row per video: id, title, channel @handle, privacy label.
      #
      # NOT stamped follow-up-able (no video_list follow-up handler exists;
      # consistent with the simplest viable choice).
      #
      # NOTE: The caller is responsible for checking videos.empty? and returning
      # an appropriate empty-state before calling this builder.
      module List
        module_function

        # @param videos       [ActiveRecord::Relation | Array<::Video>] non-empty, pre-fetched.
        # @param conversation [Conversation] used for future follow-up stamping (unused now).
        # @return [Hash] string-keyed payload with body and table_rows.
        def call(videos, conversation:)
          {
            "body"          => Pito::Copy.render("pito.copy.videos.list_intro", { count: videos.size }),
            "table_heading" => [ "#", "Title", "Channel", "Privacy" ],
            "table_rows"    => videos.map { |video| row_for(video) }
          }
        end

        def row_for(video)
          {
            cells: [
              { text: "##{video.id}",           class: "text-cyan tabular-nums text-right whitespace-nowrap" },
              { text: video.title,              class: "text-fg" },
              { text: video.channel.at_handle,  class: "text-cyan whitespace-nowrap" },
              { text: privacy_label(video),     class: "text-fg-faded whitespace-nowrap" }
            ]
          }
        end

        def privacy_label(video)
          return "" if video.privacy_status.blank?

          I18n.t("pito.video.detail.privacy_status.#{video.privacy_status}",
                 default: video.privacy_status.to_s.capitalize)
        end

        private_class_method :row_for, :privacy_label
      end
    end
  end
end
