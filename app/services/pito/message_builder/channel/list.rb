# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Channel
      # Builds the payload for the `list channels` kv-table message (the card
      # strip retired 2026-07-02 — channels list like every other list verb).
      #
      # Columns: Avatar · Handle · Title · Subs · Views · Vids, always shown —
      # plus ADDABLE columns (`with likes` / `without likes`, G26.2) appended
      # on the right. `sort` is supported on every column except Avatar, and on
      # an addable column while visible (see ListColumns). Counts are compact
      # (2.2K); the Avatar cell is the tiny (35px) ringed variant and the
      # data-grid middle-aligns row text to it.
      #
      # The Handle cell is the click-to-open seam (auto-submits
      # `show channel @handle`) — same affordance as the vids list's #id cell.
      #
      # Stamped follow-up-able (reply_target: "channel_list") with the listed
      # channel_ids, so replies (`sort`, `analyze`, `shinies`) can reload the
      # same set.
      #
      # NOTE: The caller is responsible for checking channels.empty? and
      # returning an appropriate empty-state before calling this builder.
      module List
        extend Pito::MessageBuilder::Helpers
        module_function

        HEADING = [
          "", # Avatar column — no label
          "Handle",
          "Title",
          { "text" => "Subs",  "class" => "text-right" },
          { "text" => "Views", "class" => "text-right" },
          { "text" => "Vids",  "class" => "text-right" }
        ].freeze

        # @param channels     [Array<::Channel>] non-empty, pre-fetched, pre-sorted.
        # @param conversation [Conversation] used to generate the reply handle.
        # @param columns      [Array<Symbol>] addable canonical column keys (ListColumns::COLUMNS).
        # @return [Hash] string-keyed payload with body, table, follow-up fields.
        def call(channels, conversation:, columns: [])
          cols = Array(columns).map(&:to_sym)

          heading = HEADING.map(&:dup) + cols.map { |c|
            {
              "text"  => ListColumns::COLUMNS.fetch(c)[:heading],
              "class" => "text-right pito-table-heading--added"
            }
          }

          payload = {
            "body" => Pito::Copy.render_html(
              "pito.copy.channels.list_intro",
              { count: channels.size, noun: channels.size == 1 ? "channel" : "channels" },
              shimmer: [ :count, :noun ]
            ),
            "html"            => true,
            "table_heading"   => heading,
            "shimmer_heading" => true,
            "table_rows"      => channels.map { |channel| row_for(channel, cols) },
            # Stamped so `sort` replies reload the same set and `analyze` can
            # scope the analysis to these channels.
            "channel_ids"     => channels.map(&:id),
            # Stamped so with/without/sort replies preserve the selection.
            "list_columns"    => cols.map(&:to_s),
            "list_footer"     => Pito::Lists::OptionsFooter.call(
              addable:   (ListColumns::COLUMNS.keys - cols).map(&:to_s),
              removable: cols.map(&:to_s),
              sort_keys: ListColumns.sortable_tokens(selected_columns: cols),
              noun:      "columns"
            )
          }
          Pito::FollowUp.make_followupable!(payload, target: "channel_list", conversation: conversation)
          payload
        end

        def row_for(channel, cols = [])
          handle = channel.at_handle
          {
            cells: [
              {
                text:  render_component(Pito::Channel::TinyAvatarComponent.new(channel:)),
                html:  true,
                class: "pito-cell-avatar"
              },
              {
                text:  handle,
                class: Pito::Shimmer::TokenComponent.css_class(handle, extra: "whitespace-nowrap", clickable: true),
                data:  Pito::Shimmer::TokenComponent.prefill_data("show channel #{handle}", submit: true)
              },
              { text: channel.title.to_s, class: "text-fg pito-cell-title" },
              count_cell(channel.subscriber_count),
              count_cell(channel.view_count),
              count_cell(channel.videos.count),
              *cols.map { |c| count_cell(ListColumns::COLUMNS.fetch(c)[:value].call(channel)) }
            ]
          }
        end
        private_class_method :row_for

        def count_cell(value)
          {
            text:  Pito::Formatter::CompactCount.call(value.to_i),
            class: "text-fg-dim text-right tabular-nums whitespace-nowrap"
          }
        end
        private_class_method :count_cell
      end
    end
  end
end
