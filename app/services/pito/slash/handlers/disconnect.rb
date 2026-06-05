# frozen_string_literal: true

module Pito
  module Slash
    module Handlers
      # /disconnect @handle   — case-sensitive partial match on Channel#handle
      # /disconnect <id>      — local numeric id
      #
      # Returns an error event if the channel cannot be resolved.
      # Returns a confirmation event with expand_detail breakdown if found.
      class Disconnect < Pito::Slash::Handler
        self.verb = :disconnect
        self.description_key = "pito.slash.disconnect.descriptions.disconnect"

        grammar do
          enum :channel, source: :channels, optional: true
          auth :authenticated_only
          description_key "pito.grammar.slash.disconnect"
        end

        def call
          target = parse_target
          return missing_target_error if target.blank?

          channel = resolve_channel(target)
          return not_found_error(target) if channel.nil?

          confirmation_event(channel)
        end

        private

        def parse_target
          parts = invocation.raw.strip.split(/\s+/, 2)
          parts.length == 2 ? parts.last.strip.presence : nil
        end

        # Case-sensitive: @Johndoe and @johnDoe are distinct channels.
        def resolve_channel(target)
          if target.start_with?("@")
            fragment = target.delete_prefix("@")
            Channel.where("handle LIKE ?", "%#{fragment}%").first
          elsif target.match?(/\A\d+\z/)
            Channel.find_by(id: target.to_i)
          else
            Channel.where("handle LIKE ?", "%#{target}%").first
          end
        end

        def missing_target_error
          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "error",
              payload: { text: I18n.t("pito.slash.disconnect.errors.missing_target") }
            }
          ])
        end

        def not_found_error(target)
          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "error",
              payload: { text: I18n.t("pito.slash.disconnect.errors.not_found", target: target) }
            }
          ])
        end

        def confirmation_event(channel)
          handle     = channel.handle.presence || channel.title.to_s
          conf_handle = Pito::HandleGenerator.call(conversation)

          Pito::Slash::Result::Ok.new(events: [
            {
              kind:    "confirmation",
              payload: {
                command:             "disconnect",
                body:                I18n.t("pito.slash.disconnect.confirmation.body", handle_html: %(<span class="text-cyan">@#{handle.delete_prefix("@")}</span>)),
                html:                true,
                confirmation_handle: conf_handle,
                channel_id:          channel.id,
                expand_detail:       build_expand_detail(channel)
              }
            }
          ])
        end

        def build_expand_detail(channel)
          published   = channel.videos.privacy_status_public.count
          private_all = channel.videos.privacy_status_private.count
          scheduled   = channel.videos.privacy_status_private.where.not(publish_at: nil).count
          private_v   = private_all - scheduled
          unlisted    = channel.videos.privacy_status_unlisted.count
          total       = published + private_all + unlisted

          t = ->(key) { I18n.t("pito.slash.disconnect.confirmation.expand.#{key}") }
          v = ->(n) { Pito::Formatter::CompactCount.call(n) }

          [
            # Channel stats first
            { key: t.call(:subscribers),   value: v.call(channel.subscriber_count.to_i) },
            { key: t.call(:views),           value: v.call(channel.view_count.to_i) },
            { key: t.call(:watched_hours),   value: v.call(channel.watched_hours) },
            # Separator
            "",
            # Video breakdown
            { key: t.call(:total),    value: total.to_s },
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
