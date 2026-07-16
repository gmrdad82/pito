# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Conversation
      # Builds the payload for a conversation-SEARCH hits card, rendered via the
      # generic Pito::Event::SystemComponent data grid (table_heading/table_rows),
      # same mechanism as Video::List. Wired from
      # Pito::Chat::Handlers::SearchConversations#ok.
      #
      # 3.0.0 L3 owner-locked shape: TWO columns, mode-dependent — a hit is
      # EITHER a `like` (semantic) hit or a `for`/bare (lexical) hit, never
      # both, and every hit in one `call` shares the same mode (see
      # SearchConversations#build_hits: "score" rides on the `like` path,
      # "occurrence_count" on the `for`/bare path, the other left nil).
      #
      #   like: "Conversation" | "Similarity"  — a 0-100 score bar (the SAME
      #         { score: } cell shape/ScoreBarComponent the similar-games /
      #         channel-recommendation cards use), rescaled from the measured
      #         embedding-space floor (see Pito::Recommendation::DisplayScore)
      #         so it actually discriminates real hits from background noise.
      #         Labeled "Similarity", not "Score"/"Match": this number is raw
      #         cosine similarity (rescaled), unlike games' 10-signal blended
      #         "Match" score (lib/pito/message_builder/game/list.rb).
      #   for:  "Conversation" | "Occurrences" — how many matching events
      #         grouped into that conversation within the candidate pool.
      #
      # There is no snippet column and no anchor "#<id>" column (dropped in
      # 3.0.0 — the conversation name cell is now the click affordance, see
      # below, and the raw anchor id added little on its own).
      #
      # == The conversation name cell is a `/resume` click-to-submit token
      #
      # Same prefill/auto-submit seam Video::List's `#<id>` cell uses
      # (Pito::Shimmer::TokenComponent.prefill_data(…, submit: true) merged
      # into the cell's `data:`, `.css_class(…, clickable: true)` for the
      # matching action-shimmer styling) — clicking the conversation title
      # types AND submits a `/resume` command:
      #   like: "/resume <conversation_uuid>"
      #   for:  "/resume <conversation_uuid> <anchor_event_id>" — the anchor
      #         event id is passed so resume jumps straight to the first
      #         (chronologically earliest-in-pool) occurrence.
      #
      # == The row-level `data` contract (do not drop)
      #
      # Every row ALSO carries `data: { "anchor_event_id" => …,
      # "conversation_uuid" => … }`. Pito::Event::SystemComponent
      # #normalized_table_rows stamps a row's `:data` onto EVERY cell span of
      # that row (there is no single per-row DOM element — see that method's
      # comment) and merges it under any per-cell `:data` (the name cell's
      # prefill data wins on key collision; there is none here since the key
      # sets don't overlap) — this is what lets the `pito--anchor-jump`
      # Stimulus controller (app/javascript/controllers/pito/anchor_jump_
      # controller.js) find `[data-anchor-event-id]` on a click anywhere in
      # the row and smooth-scroll the scrollback to `#event_<id>` — a graceful
      # no-op when the hit is from another conversation (its event isn't in
      # this DOM). `conversation_uuid` rides along for the same reason the
      # name cell's `/resume` command needs it: a hit can only be fetched by
      # uuid cross-conversation.
      #
      # == NOT follow-up-able
      #
      # Unlike Video::List, a hit is navigated by CLICKING the conversation
      # name (or, within the same conversation, anywhere in the row via the
      # anchor-jump data above) — not by replying `#<handle> …` — so this
      # builder never calls Pito::FollowUp.make_followupable!.
      module Hits
        module_function

        LIKE_TABLE_HEADING = [ "Conversation", "Similarity" ].freeze
        FOR_TABLE_HEADING  = [ "Conversation", "Occurrences" ].freeze

        # @param hits         [Array<Hash>]  non-empty; each a string-keyed hit
        #                                    ("title", "anchor_event_id",
        #                                    "conversation_uuid", "occurrence_count",
        #                                    "score") — see
        #                                    Pito::Chat::Handlers::SearchConversations#build_hits.
        #                                    All hits share one mode: "score"
        #                                    non-nil ⇒ like (semantic), else for
        #                                    (lexical).
        # @param conversation [::Conversation] the current conversation. Unused
        #                                    today (this card isn't follow-up-able)
        #                                    but kept in the signature for parity
        #                                    with every other MessageBuilder list
        #                                    (Video::List, Channel::Videos, …) so a
        #                                    future follow-up-able variant needs no
        #                                    call-site change.
        # @return [Hash] string-keyed payload: body, html, table_heading, table_rows.
        def call(hits, conversation:) # rubocop:disable Lint/UnusedMethodArgument
          like = like_mode?(hits)
          {
            "body"          => Pito::Copy.render_html(
              "pito.copy.conversations.hits_intro",
              { count: hits.size, noun: hits.size == 1 ? "conversation" : "conversations" },
              shimmer: [ :count, :noun ]
            ),
            "html"          => true,
            "table_heading" => like ? LIKE_TABLE_HEADING : FOR_TABLE_HEADING,
            "table_rows"    => hits.map { |hit| row_for(hit, like: like) },
            "list_footer"   => Pito::Copy.render(like ? "pito.copy.search.footer_like" : "pito.copy.search.footer_for")
          }
        end

        # A hit's mode is determined by whether the FIRST hit carries a
        # non-nil "score" (stamped only on the semantic `like` path — see
        # SearchConversations#rank_by_distance / #rank_by_recency). Every hit
        # in one `call` shares the same mode, so checking the first is enough.
        def like_mode?(hits)
          !hits.first["score"].nil?
        end

        def row_for(hit, like:)
          {
            cells: like ? like_cells(hit) : for_cells(hit),
            data: {
              "anchor_event_id"   => hit["anchor_event_id"],
              "conversation_uuid" => hit["conversation_uuid"]
            }
          }
        end

        def like_cells(hit)
          [
            name_cell(hit, resume_command: "/resume #{hit['conversation_uuid']}"),
            { score: hit["score"].to_i }
          ]
        end

        def for_cells(hit)
          [
            name_cell(hit, resume_command: "/resume #{hit['conversation_uuid']} #{hit['anchor_event_id']}"),
            { text: hit["occurrence_count"].to_s, class: "tabular-nums text-right whitespace-nowrap" }
          ]
        end

        # The conversation-name cell: clickable, same action-shimmer styling
        # and chat-prefill/auto-submit data Video::List's `#<id>` cell uses
        # (Pito::Shimmer::TokenComponent), typing+submitting `resume_command`
        # on click. `pito-cell-title` caps the column width the same way the
        # dropped plain title cell did.
        def name_cell(hit, resume_command:)
          title = hit["title"].to_s
          {
            text:  title,
            class: Pito::Shimmer::TokenComponent.css_class(title, extra: "pito-cell-title", clickable: true),
            data:  Pito::Shimmer::TokenComponent.prefill_data(resume_command, submit: true)
          }
        end

        private_class_method :like_mode?, :row_for, :like_cells, :for_cells, :name_cell
      end
    end
  end
end
