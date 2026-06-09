# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Video
      # Builds the payload for the video library list message.
      #
      # Returns a table_rows payload (kv-table via SystemComponent) with a
      # 4-column cells row per video: id, title, channel @handle, privacy label.
      #
      # Stamped follow-up-able (reply_target: "video_list") so the user can reply
      # `#<handle> show <id>` / `rm <id>` etc. — delegated to the verb handlers.
      #
      # NOTE: The caller is responsible for checking videos.empty? and returning
      # an appropriate empty-state before calling this builder.
      module List
        module_function

        # @param videos       [ActiveRecord::Relation | Array<::Video>] non-empty, pre-fetched.
        # @param conversation [Conversation] used to generate the reply handle.
        # @param columns      [Array<Symbol>] extra canonical column keys (from ListColumns).
        # @return [Hash] string-keyed payload with body, table_rows, and follow-up fields.
        def call(videos, conversation:, columns: [])
          payload = {
            "body"          => Pito::Copy.render("pito.copy.videos.list_intro", { count: videos.size }),
            "table_heading" => [ "#", "Title", "Channel", "Privacy", *ListColumns.headings(columns) ],
            "table_rows"    => videos.map { |video| row_for(video, columns) }
          }
          Pito::FollowUp.make_followupable!(payload, target: "video_list", conversation: conversation)
          payload
        end

        def row_for(video, columns = [])
          {
            cells: [
              { text: "##{video.id}",           class: "text-cyan tabular-nums text-right whitespace-nowrap" },
              { text: video.title,              class: "text-fg" },
              { text: video.channel.at_handle,  class: "text-cyan whitespace-nowrap" },
              { text: privacy_label(video),     class: "text-fg-faded whitespace-nowrap" },
              *ListColumns.cells(video, columns)
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
