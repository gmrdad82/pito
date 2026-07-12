# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Channel
      # Builds the `:enhanced` channel-videos list shown under a channel detail
      # (`show channel @handle`). Wraps Video::List so the table is identical to
      # the standalone vid library + the show-game linked-videos list — and
      # inherits its `video_list` follow-up target, so the user can reply
      # `#<handle> show <id>`, sort, with/without columns, etc.
      #
      # The generic vids list_intro is replaced with a channel-scoped witty intro
      # (its own 50-variant dict). The `channel` column is dropped — every row is
      # the same channel here.
      #
      # NOTE: caller checks channel.videos.any? and skips this for an empty channel.
      # NAMESPACE: `Channel` is the MessageBuilder sub-module; use ::Channel / the
      # passed record for the model.
      module Videos
        module_function

        # Per-video columns for a channel's vids (no channel column — all one
        # channel; :comments left with the vids-list comms column).
        COLUMNS = %i[duration views likes].freeze

        # @param channel      [::Channel]    the channel whose videos to list.
        # @param conversation [Conversation] used to generate the reply handle.
        # @return [Hash] string-keyed table_rows payload, follow-up stamped (video_list).
        def call(channel, conversation:)
          videos  = channel.videos
          payload = Pito::MessageBuilder::Video::List.call(videos, conversation: conversation, columns: COLUMNS)
          payload["body"] = Pito::Copy.render_html(
            "pito.copy.channels.videos_intro",
            { count: videos.size, title: channel.title },
            shimmer: [ :title ]
          )
          payload["html"] = true
          payload
        end
      end
    end
  end
end
