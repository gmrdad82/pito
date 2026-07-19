# frozen_string_literal: true

module Pito
  module Lists
    # Generic, domain-agnostic "which channel(s) is this from" clause, appended
    # to a list intro body (E-something — the single-channel column noise fix).
    #
    # A single-channel library shows the SAME truncated @handle down an entire
    # column — pure noise. Rather than render that column, the channel belongs
    # in the intro once, as a reference: a single channel names its @handle;
    # multiple channels enumerate a capped few plus a "+N more" tail. Both
    # forms compose via Pito::Copy.render_html's `reference:` kwarg (the cyan
    # pito-token span — same mechanism as analyze/message.rb's period token),
    # so the whole clause renders as ONE token, never a per-handle span.
    #
    # Callers (Video::List / Game::List) decide the FULL, un-paginated result
    # set's distinct channels ONCE (never per-page — see the chat handler's
    # channel-context helpers) and hand that Array here alongside the
    # already-rendered intro body.
    module ChannelReference
      # How many @handles the multi-channel clause names before collapsing the
      # rest into "+N more" — mirrors the games :channels cell's own cap
      # (game/list_columns.rb), just applied to more than the first one.
      CAP = 3

      module_function

      # @param body     [ActiveSupport::SafeBuffer] the rendered intro (html_safe)
      # @param channels [Array<String>] distinct @handles for the full result
      #   set (any order — multi-channel callers should hand these pre-sorted).
      #   Blank/empty means "nothing to add" — body returns unchanged.
      # @return [ActiveSupport::SafeBuffer]
      def append(body, channels)
        return body if channels.blank?

        clause =
          if channels.size == 1
            Pito::Copy.render_html(
              "pito.copy.list.channel_reference",
              { channel: channels.first },
              reference: [ :channel ]
            )
          else
            Pito::Copy.render_html(
              "pito.copy.list.channels_reference",
              { channels: enumerate(channels) },
              reference: [ :channels ]
            )
          end

        helpers.safe_join([ body, clause ], " ")
      end

      # "@a, @b, @c +2 more" — the first CAP handles, comma-joined, with a
      # trailing count for the rest; no "+N more" suffix when everything fit.
      #
      # @param channels [Array<String>]
      # @return [String]
      def enumerate(channels)
        shown = channels.first(CAP)
        rest  = channels.size - shown.size
        rest.positive? ? "#{shown.join(', ')} +#{rest} more" : shown.join(", ")
      end

      def helpers
        ActionController::Base.helpers
      end
      private_class_method :helpers
    end
  end
end
