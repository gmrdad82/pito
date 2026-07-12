# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Video
      # Builds the payload for the video library list message.
      #
      # Returns a table_rows payload (kv-table via SystemComponent). The default
      # row is just id + title; `channel`, `visibility`, and the rest are optional
      # `with` columns (see Video::ListColumns).
      #
      # Stamped follow-up-able (reply_target: "video_list") so the user can reply
      # `#<handle> show <id>` / `rm <id>` etc. — delegated to the tool handlers.
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
          cols    = Array(columns).map(&:to_sym)
          payload = {
            "body"          => Pito::Copy.render_html(
              "pito.copy.videos.list_intro",
              { count: videos.size, noun: videos.size == 1 ? "vid" : "vids" },
              shimmer: [ :count, :noun ]
            ),
            "html"          => true,
            "table_heading" => [ { "text" => "#", "class" => "text-right" }, "Title", *ListColumns.heading_cells(cols) ],
            "shimmer_heading" => true,
            "table_rows"    => videos.map { |video| row_for(video, cols) },
            # Stamped for with/without column mutations: allows the handler to
            # reload the same videos and rebuild with an updated column set.
            "video_ids"     => videos.map(&:id),
            "list_columns"  => cols.map(&:to_s),
            "list_footer"   => ListColumns.options_footer(cols)
          }
          Pito::FollowUp.make_followupable!(payload, target: "video_list", conversation: conversation)
          payload
        end

        def row_for(video, columns = [])
          id_text = "##{video.id}"
          {
            cells: [
              {
                text:  id_text,
                class: Pito::Shimmer::TokenComponent.css_class(id_text, extra: "tabular-nums text-right whitespace-nowrap", clickable: true),
                # Click-to-open: same chat-prefill seam as the detail card #id —
                # clicking the cell auto-submits `show vid #<id>` (J5, and J12
                # when this list is the enhanced linked-videos table).
                data:  Pito::Shimmer::TokenComponent.prefill_data("show vid #{id_text}", submit: true)
              },
              { text: video.title, class: "text-fg pito-cell-title" },
              *ListColumns.cells(video, columns)
            ]
          }
        end

        private_class_method :row_for
      end
    end
  end
end
