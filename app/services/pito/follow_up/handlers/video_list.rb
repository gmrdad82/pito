# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for `list videos` messages (reply_target: "video_list").
      #
      # A thin shim: allowed reply verbs are handed to VerbDelegator (show/delete/rm),
      # which resolves the reference among the list's rows and wraps the result.
      #
      #   #<handle> show <id|title>  → the video detail card + enhanced message
      #   #<handle> rm | delete <id> → the video delete confirmation
      #   #<handle> schedule <id> <when> → the schedule confirmation
      #   #<handle> publish | unlist <id> → the visibility-change confirmation
      #
      # Column mutations (no consume, :mutate mode per action):
      #   #<handle> with <columns>    → rebuild list with extra column(s)
      #   #<handle> without <columns> → rebuild list without the named column(s)
      #
      # Sort mutations (no consume, :mutate mode per action):
      #   #<handle> sort by <col> [desc]  → re-sort the stamped list in place
      #   #<handle> order by <col> [desc] → alias for sort
      #
      # The action_modes DSL declares that `with`, `without`, `sort`, and `order`
      # are :mutate (no echo, no turn, re-render the same message), while the
      # class-level mode (:append) governs show/delete/rm (consume the source,
      # echo + turn).
      class VideoList < Pito::FollowUp::Handler
        self.target "video_list"
        self.mode   :append
        self.action_modes with: :mutate, without: :mutate, sort: :mutate, order: :mutate
        self.actions "show", "delete", "rm", "schedule", "publish", "unlist",
                     "with", "without", "sort", "order", "link", "unlink", "shinies"

        def call(event:, rest:, conversation:)
          action, args = parse_rest(rest)

          case action
          when "with", "without"
            mutate_columns(event:, conversation:, action:, args:)
          when "sort", "order"
            mutate_sort(event:, conversation:, args:)
          else
            Pito::FollowUp::VerbDelegator.call(source_event: event, rest:, conversation:)
          end
        end

        private

        # Re-sort the stamped video list by a column token.
        # Strips an optional leading `by`, parses a trailing direction, and
        # resolves the sort key via Video::ListColumns.sort_key_for.  An unknown
        # or not-present column is a lenient no-op (records remain in stamped order).
        def mutate_sort(event:, conversation:, args:)
          payload = event.payload.with_indifferent_access

          current_cols = Array(payload["list_columns"]).map(&:to_sym)

          # Strip optional leading "by" particle.
          tokens = args.to_s.strip.split(/\s+/)
          tokens.shift if tokens.first&.downcase == "by"

          # Parse trailing direction token.
          direction = :asc
          if tokens.last&.downcase&.match?(/\A(?:desc|descending)\z/)
            direction = :desc
            tokens.pop
          elsif tokens.last&.downcase&.match?(/\A(?:asc|ascending)\z/)
            tokens.pop
          end

          sort_token = tokens.join(" ")

          # Reload videos by the stamped ordered ids.
          ids    = Array(payload["video_ids"])
          videos = ::Video.where(id: ids).sort_by { |v| ids.index(v.id) || ids.size }

          key = Pito::MessageBuilder::Video::ListColumns.sort_key_for(
            sort_token, selected_columns: current_cols
          )

          if key
            videos = videos.sort_by { |v| key.call(v) }
            videos.reverse! if direction == :desc
          end

          new_payload = Pito::MessageBuilder::Video::List.call(
            videos,
            conversation:,
            columns:      current_cols
          )

          new_payload["reply_handle"] = payload["reply_handle"]
          new_payload["reply_target"] = payload["reply_target"]
          # Lift the re-rendered (mutated) segment onto the surface background.
          new_payload["surface"]      = true

          Pito::FollowUp::Result::Mutation.new(
            kind:    event.kind.to_sym,
            payload: new_payload
          )
        end

        # Parse the comma-separated column list from args, compute the new set
        # (with: union; without: difference), reload the same videos, and rebuild
        # the list payload preserving the reply handle + target so it stays repliable.
        def mutate_columns(event:, conversation:, action:, args:)
          payload = event.payload.with_indifferent_access

          current_cols = Array(payload["list_columns"]).map(&:to_sym)
          vocab        = Pito::MessageBuilder::Video::ListColumns.vocabulary

          # Parse the requested delta columns from the comma-list.
          delta_cols = args.split(/\s*,\s*/).filter_map { |t|
            vocab[t.strip.downcase]
          }.uniq

          new_cols =
            case action
            when "with"    then (current_cols | delta_cols)
            when "without" then (current_cols - delta_cols)
            end

          # Reload videos by the stamped ordered ids.
          ids    = Array(payload["video_ids"])
          videos = ::Video.where(id: ids).sort_by { |v| ids.index(v.id) || ids.size }

          # Build the new payload via the same List builder.
          new_payload = Pito::MessageBuilder::Video::List.call(
            videos,
            conversation:,
            columns:      new_cols
          )

          # Preserve the original handle so the same #<handle> keeps working.
          new_payload["reply_handle"] = payload["reply_handle"]
          new_payload["reply_target"] = payload["reply_target"]
          # Lift the re-rendered (mutated) segment onto the surface background.
          new_payload["surface"]      = true

          Pito::FollowUp::Result::Mutation.new(
            kind:    event.kind.to_sym,
            payload: new_payload
          )
        end
      end
    end
  end
end
