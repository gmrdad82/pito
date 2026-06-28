# frozen_string_literal: true

module Pito
  module FollowUp
    # Shared builder for an `analyze` follow-up REPLY — turns a stamped scope (a
    # list's ids, or a detail card's single entity) into the analyze :system +
    # :enhanced pair, mirroring the `analyze` chat verb's scope-title rules
    # (Pito::Chat::Handlers::Analyze#scope_title) so a replied analysis reads
    # exactly like a typed one.
    #
    # Returns a Result::Append: the pair lands as a fresh :system turn, so the
    # Finalizer's consume retires the prior live handles (the list / detail is
    # "done", you're in analyze now) — same lifecycle as the glance's analyze reply.
    #
    # NAMESPACE: `::Video`/`::Game`/`::Channel` for models; `Pito::*` for services.
    module AnalyzeReply
      PLURALS = { vid: "vids", game: "games", channel: "channels" }.freeze

      module_function

      # @param level        [Symbol] :vid | :game | :channel
      # @param ids          [Array<Integer>] the scope entity ids (≥ 1)
      # @param conversation [Conversation]
      # @param period       [String, nil] reply period override → conversation.stats_period
      def append(level:, ids:, conversation:, period: nil)
        pair = Pito::MessageBuilder::Analyze::Message.pair(
          level:,
          entity_ids: ids,
          title:      scope_title(level, ids),
          period:     period.presence || conversation.stats_period,
          conversation:,
          selection:  nil
        )
        Pito::FollowUp::Result::Append.new(events: pair)
      end

      # A single entity's name/handle, or "N <plural>" for a multi-entity scope.
      def scope_title(level, ids)
        return "your #{PLURALS.fetch(level, "channels")}" if ids.empty?
        return single_title(level, ids.first) if ids.one?

        "#{ids.size} #{PLURALS.fetch(level, level.to_s)}"
      end

      def single_title(level, id)
        record =
          case level
          when :vid     then ::Video.find_by(id:)
          when :game    then ::Game.find_by(id:)
          when :channel then ::Channel.find_by(id:)
          end
        return PLURALS.fetch(level, level.to_s) unless record

        record.respond_to?(:at_handle) ? record.at_handle : record.title
      end
    end
  end
end
