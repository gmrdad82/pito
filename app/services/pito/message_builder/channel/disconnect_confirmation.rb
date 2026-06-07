# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Channel
      # Builds the payload for a "disconnect this channel?" confirmation.
      #
      # The destroy happens in Pito::Confirmation::Executor on `#<handle> confirm`.
      # The payload includes an expand_detail array (channel stats + video breakdown)
      # so the confirmation dialog shows full context before the user commits.
      module DisconnectConfirmation
        module_function

        # @param channel      [::Channel]
        # @param conversation [Conversation] — used to mint the reply handle.
        # @return [Hash] a follow-up-able confirmation payload (target: confirmation).
        def call(channel, conversation:)
          handle = channel.handle.presence || channel.title.to_s
          handle_html = %(<span class="text-cyan">@#{handle.delete_prefix("@")}</span>)

          payload = {
            "command"       => "disconnect",
            "body"          => Pito::Copy.render("pito.copy.disconnect.confirmation_body", { handle_html: handle_html }),
            "html"          => true,
            "channel_id"    => channel.id,
            "expand_detail" => expand_detail(channel)
          }
          Pito::FollowUp.make_followupable!(payload, target: "confirmation", conversation:)
          payload
        end

        def expand_detail(channel)
          published   = channel.videos.privacy_status_public.count
          private_all = channel.videos.privacy_status_private.count
          scheduled   = channel.videos.privacy_status_private.where.not(publish_at: nil).count
          private_v   = private_all - scheduled
          unlisted    = channel.videos.privacy_status_unlisted.count
          total       = published + private_all + unlisted

          t = ->(key) { I18n.t("pito.slash.disconnect.confirmation.expand.#{key}") }
          v = ->(n) { Pito::Formatter::CompactCount.call(n) }

          [
            { key: t.call(:subscribers), value: v.call(channel.subscriber_count.to_i) },
            { key: t.call(:views),       value: v.call(channel.view_count.to_i) },
            "",
            { key: t.call(:total),     value: total.to_s },
            { key: t.call(:published), value: v.call(published) },
            { key: t.call(:scheduled), value: v.call(scheduled) },
            { key: t.call(:unlisted),  value: v.call(unlisted) },
            { key: t.call(:private),   value: v.call(private_v) }
          ]
        end
      end
    end
  end
end
