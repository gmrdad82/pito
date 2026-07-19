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
        # @param scores       [Hash{Integer => Integer}, nil] optional video_id => 0..100 score
        #   map (search's `like` path). When present, a trailing Similarity column is appended
        #   to the heading and every row via the `{ score: }` data-grid cell contract (renders
        #   a score bar — see Pito::Event::SystemComponent#normalized_cell). nil (every other
        #   caller: `list vids`, follow-up pagers) → no Similarity column, output identical to
        #   before this param existed.
        # @param channels [Array<String>] distinct @handles for the FULL (un-paginated) result
        #   set — decided once by the chat handler, never per-page. Appended to the intro body
        #   as a reference clause via Pito::Lists::ChannelReference: one handle names itself,
        #   several enumerate with a cap. [] (every other caller) → no clause, output identical
        #   to before this param existed.
        # @param suppressed_columns [Array<Symbol>] columns withheld for THIS list only (e.g.
        #   :channel when `channels` collapses to a single handle) — excluded from the options
        #   footer's addable set and stamped so with/without follow-ups can reject them too.
        # @return [Hash] string-keyed payload with body, table_rows, and follow-up fields.
        def call(videos, conversation:, columns: [], scores: nil, channels: [], suppressed_columns: [])
          cols       = Array(columns).map(&:to_sym)
          suppressed = Array(suppressed_columns).map(&:to_sym)
          payload = {
            "body"          => Pito::Lists::ChannelReference.append(
              Pito::Copy.render_html(
                "pito.copy.videos.list_intro",
                { count: videos.size, noun: videos.size == 1 ? "vid" : "vids" },
                shimmer: [ :count, :noun ]
              ),
              channels
            ),
            "html"          => true,
            "table_heading" => [
              { "text" => "#", "class" => "text-right" },
              "Title",
              *ListColumns.heading_cells(cols),
              # Search's `like` path only (scores present) — a literal structural
              # label, same as the plain-string "Title" heading above. "Similarity",
              # not "Score"/"Match": a vid like-score is 100% raw cosine similarity,
              # rescaled from the embedding space's measured "everything looks
              # alike" floor (see Pito::Recommendation::DisplayScore) — unlike
              # games' 10-signal blended "Match" score, this number IS a
              # similarity, so it's labeled as one. Conversation::Hits uses the
              # same "Similarity" heading for its own `like`-path score column
              # (lib/pito/message_builder/conversation/hits.rb).
              *(scores ? [ "Similarity" ] : [])
            ],
            "shimmer_heading" => true,
            "table_rows"    => videos.map { |video| row_for(video, cols, scores: scores) },
            # Stamped for with/without column mutations: allows the handler to
            # reload the same videos and rebuild with an updated column set.
            "video_ids"     => videos.map(&:id),
            "list_columns"  => cols.map(&:to_s),
            # Stamped so with/without follow-ups (and later pages) can keep
            # rejecting a per-list-suppressed column instead of silently
            # re-adding it — see Pito::FollowUp::Handlers::VideoList#mutate_columns.
            "suppressed_columns" => suppressed.map(&:to_s),
            "list_footer"   => ListColumns.options_footer(cols, suppressed:)
          }
          Pito::FollowUp.make_followupable!(payload, target: "video_list", conversation: conversation)
          payload
        end

        def row_for(video, columns = [], scores: nil)
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
              *ListColumns.cells(video, columns),
              # { score: } cell contract (SystemComponent#normalized_cell) —
              # renders a ScoreBarComponent instead of plain text.
              *(scores ? [ { score: scores[video.id] } ] : [])
            ]
          }
        end

        private_class_method :row_for
      end
    end
  end
end
