# frozen_string_literal: true

module Pito
  module Bench
    module Steps
      # Replay bench — renders EVERY event of one conversation exactly the way
      # `GET /chat/:uuid` does (`Pito::Stream::EventRenderer` per event), timing
      # the full pass plus a per-kind breakdown. This is the number the L1
      # message-fragment and L2 snapshot caches (0.9.0 Phases 5–6) must beat.
      #
      # Conversation choice: `ctx.uuid` when given, else the conversation with
      # the most events (the worst realistic page load).
      module Replay
        module_function

        def label = "replay"

        # @param ctx [Pito::Bench::Runner::Ctx]
        # @return [Hash] events count, total/avg ms, per-kind ms buckets
        def call(ctx)
          conversation = find_conversation(ctx.uuid)
          return { "skipped" => "no conversation found" } if conversation.nil?

          events   = conversation.events.includes(:turn).order(:position).to_a
          per_kind = Hash.new(0.0)

          # Warm-up pass (untimed): first renders pay autoload + template compile
          # for the whole component tree, which would otherwise pile into whatever
          # kind happens to render first. We compare steady-state numbers.
          events.each { |event| Pito::Stream::EventRenderer.render(event) }

          t0 = clock
          events.each do |event|
            t = clock
            Pito::Stream::EventRenderer.render(event)
            per_kind[event.kind] += clock - t
          end
          total_ms = (clock - t0) * 1000

          {
            "uuid"     => conversation.uuid,
            "events"   => events.size,
            "total_ms" => total_ms.round(2),
            "avg_ms"   => events.empty? ? 0 : (total_ms / events.size).round(3)
          }.merge(per_kind.transform_keys { |k| "#{k}_ms" }.transform_values { |s| (s * 1000).round(2) })
        end

        # ::Conversation — the domain model, NOT Pito::Conversation (services).
        def find_conversation(uuid)
          return ::Conversation.find_by(uuid: uuid) if uuid.present?

          ::Conversation.left_joins(:events)
                        .group(:id)
                        .order(Arel.sql("COUNT(events.id) DESC"))
                        .first
        end

        def clock
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
