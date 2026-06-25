# frozen_string_literal: true

# Handler for the `analyze` chat verb (aliases: `analytics`, `stats`).
#
# Interval-aware YouTube analytics scoped to a channel, vid, or game. Resolves the
# scope via Pito::Analytics::ScopeResolver (entity arg + shift+tab channel scope),
# the period from shift+space (conversation.stats_period). On a resolvable scope it
# emits TWO pending messages — a :system and an :enhanced card (each with its own
# Pito::Copy intro) — and returns immediately; the Finalizer enqueues
# AnalyzePrepareJob, which fans out per-video / per-channel primitives, aggregates,
# fills both messages, and resolves each message's own thinking indicator (so each
# "thought for xx.xxs" spans its full fan-out). Bare `analyze` suggests options;
# an unresolvable scope surfaces the matching error copy.
module Pito
  module Chat
    module Handlers
      class Analyze < Pito::Chat::Handler
        self.verb = :analyze
        self.description_key = "pito.chat.analyze.descriptions.analyze"

        PLURALS = { "channel" => "channels", "vid" => "vids", "game" => "games" }.freeze

        def call
          result = Pito::Analytics::ScopeResolver.call(
            raw: message.raw, channel_scope: channel.presence || conversation.scope_channel
          )

          case result.status
          when :ok    then ok_events(result)
          when :error then text_event("errors.#{result.error_key}", **result.error_args)
          else             text_event("suggest")
          end
        end

        private

        # Two pending cards (system + enhanced); AnalyzePrepareJob (enqueued by the
        # Finalizer's analyze-pending gate) fills + resolves them.
        def ok_events(result)
          events = Pito::MessageBuilder::Analyze::Message.pair(
            level:        result.level,
            entity_ids:   result.scopes.map(&:id),
            title:        scope_title(result),
            period:       analytics_period,
            conversation:,
            selection:    Pito::Analytics::MetricSelection.parse(message.raw)
          )
          Pito::Chat::Result::Ok.new(events:)
        end

        def text_event(key, **args)
          payload = Pito::MessageBuilder::Text.call("pito.copy.analyze.#{key}", **args)
          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: } ])
        end

        # Display title for the scope: a single entity's name/handle, or "N <plural>".
        def scope_title(result)
          scopes = result.scopes
          return "your #{PLURALS.fetch(result.level.to_s, "channels")}" if scopes.empty?
          return entity_title(scopes.first) if scopes.one?

          "#{scopes.size} #{PLURALS.fetch(result.level.to_s, result.level.to_s)}"
        end

        def entity_title(entity)
          entity.respond_to?(:at_handle) ? entity.at_handle : entity.title
        end

        def analytics_period
          period.presence || conversation.stats_period
        end
      end
    end
  end
end
