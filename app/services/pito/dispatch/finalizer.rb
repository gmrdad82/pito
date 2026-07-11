# frozen_string_literal: true

module Pito
  module Dispatch
    # Shared post-dispatch lifecycle for BOTH the typed (ChatDispatchJob) and the
    # reply (FollowUpDispatchJob) pipelines. Unifying it here is what guarantees a
    # verb reached via a `#<handle>` reply persists + completes IDENTICALLY to the
    # same verb typed in free chat.
    #
    # Given a list of `{ kind:, payload: }` event attrs and a turn, it:
    #   1. canonicalises handler-emitted `:system` kinds (first → :system, the
    #      rest → :enhanced; `follow_up: true` payloads → the *_follow_up
    #      variants) — see #canonical_kinds,
    #   2. persists each as an Event (`create_with_position!`) + broadcasts it,
    #      giving EACH message its OWN thinking indicator positioned immediately
    #      before it: the first message REUSES the pre-dispatch placeholder the
    #      controller emitted (so there's no no-spinner gap during dispatch),
    #      messages 2..N each get a fresh indicator emitted just before them. Each
    #      indicator is linked to its message via payload `for_event_id` so it can
    #      be resolved EXACTLY when that message is ready — see #persist,
    #   3. runs the analytics-fill gate (#complete) — resolves the indicator of
    #      every READY message now; if any persisted event is a pending analytics
    #      marker, enqueue AnalyticsFillJob (deferring that message's indicator
    #      resolve + turn completion to it so its spinner keeps cycling until the
    #      data lands); otherwise resolve all remaining indicators and complete
    #      the turn now. The turn completes only once ALL indicators are resolved.
    #
    # The error path (#surface_error) emits a visible :error event so the user is
    # never left watching a spinning indicator, then resolves + completes. Callers
    # re-raise after it so SolidQueue marks the job failed and can retry.
    #
    # NOT owned here (pipeline-specific, deliberately left in the jobs):
    #   - the turn-less :mutate reply path (replace_event + broadcast_done),
    #   - consuming the source event on a reply append,
    #   - auth gating (chat worker-side; reply controller-side).
    class Finalizer
      def initialize(conversation:, broadcaster: nil)
        @conversation = conversation
        @broadcaster  = broadcaster || Pito::Stream::Broadcaster.new(conversation:)
      end

      # Persist + broadcast `events` under `turn`, then run the completion gate.
      # The one-shot path for the typed pipeline and reply errors.
      # @return [Array<Event>] the persisted rows.
      def append_and_complete(events:, turn:)
        persisted = persist(events:, turn:)
        complete(turn:, events: persisted)
        persisted
      end

      # Canonicalise + persist + broadcast each `{ kind:, payload: }`, WITHOUT
      # completing the turn. Lets callers interleave their own steps (the reply
      # pipeline consumes the source event here) between persist and #complete.
      #
      # Each message gets its OWN thinking indicator positioned immediately
      # before it: the first message reuses the pre-dispatch placeholder (the
      # controller already emitted + broadcast it, so the spinner is continuous
      # through dispatch latency); messages 2..N each get a fresh indicator
      # emitted just before them. Every indicator is linked to its message via
      # payload `for_event_id` so #complete / AnalyticsFillJob can resolve the
      # exact one when THAT message is ready.
      # @return [Array<Event>] the persisted rows.
      # Kinds whose arrival retires all prior live #hashtags (a new "leading"
      # message — a chat verb or a reply-that-appends — supersedes old affordances,
      # so only the newest turn stays repliable).
      CONSUME_TRIGGER_KINDS = %w[system system_follow_up confirmation confirmation_follow_up].freeze

      # Kinds whose persisted events receive an auto-stamped reply_handle so that
      # universal share/revoke/unshare verbs work on any addressed message.
      HANDLE_STAMP_KINDS = %w[system enhanced confirmation].freeze

      # @param retire_prior_hashtags [Boolean] when true (the default — every typed
      #   chat verb, and any reply that consumes its source), a new
      #   :system/:confirmation message sweeps all PRIOR live #hashtags. Repeatable
      #   replies (link/unlink — `Append consume: false`, the source card stays live)
      #   pass false so the sweep is suppressed and nothing is disturbed.
      def persist(events:, turn:, retire_prior_hashtags: true)
        placeholder = unresolved_unlinked_indicator(turn)
        dictionary  = placeholder&.payload&.[]("dictionary").presence || "chat"

        # The verb that produced this turn's messages, stamped on each payload so
        # the palette and the follow-up dispatch can honor a per-verb
        # `universal_reply: false` opt-out (verbs.yml) long after emission. An
        # opted-out verb's messages get NO universal-only handle at all.
        origin_verb  = Pito::Dispatch::UniversalReply.origin_verb(turn)
        universal_ok = !Pito::Dispatch::UniversalReply.opted_out?(origin_verb)

        persisted = canonical_kinds(events).map do |attrs|
          indicator   = placeholder || @broadcaster.emit_thinking(turn:, dictionary:)
          placeholder = nil # only the first message reuses the pre-dispatch placeholder

          attrs[:payload]["origin_verb"] = origin_verb if origin_verb && !attrs[:payload].frozen?
          if universal_ok && HANDLE_STAMP_KINDS.include?(attrs[:kind].to_s)
            Pito::FollowUp.ensure_handle!(attrs[:payload], conversation: @conversation)
          end
          event = ::Event.create_with_position!(
            conversation: @conversation, turn:, kind: attrs[:kind], payload: attrs[:payload]
          )
          @broadcaster.broadcast_event(event)

          link_indicator(indicator, to: event)
          event
        end

        # A new :system / :confirmation turn retires all PRIOR live hashtags — applies
        # uniformly to typed chat verbs AND replies-that-append (a progression). Mutate
        # replies emit no new event here, and repeatable replies opt out via
        # retire_prior_hashtags:false, so both correctly leave handles live.
        if retire_prior_hashtags && persisted.any? { |e| CONSUME_TRIGGER_KINDS.include?(e.kind) }
          @broadcaster.consume_prior_live_replies(before_turn: turn)
        end

        persisted
      end

      # Completion gate. Resolves the indicator of every READY message now. When
      # any persisted event is still a pending analytics marker, defers to
      # AnalyticsFillJob (it fills the data, resolves THAT message's indicator,
      # then completes the turn). Otherwise resolves every remaining indicator and
      # completes the turn — the turn completes only once ALL indicators resolve.
      def complete(turn:, events:)
        analytics    = events.select { |e| Pito::MessageBuilder::Analytics::Enhanced.pending?(e) }
        analyze      = events.select { |e| Pito::MessageBuilder::Analyze::Message.pending?(e) }
        distribution = events.select { |e| Pito::MessageBuilder::Game::Channels.pending?(e) }
        ai           = events.select { |e| AiOrchestratorJob.pending?(e) }
        deferred     = analytics + analyze + distribution + ai

        if deferred.any?
          # Resolve the ready messages' indicators now; leave the pending ones
          # spinning for their async filler to resolve + complete. Each pending
          # KIND has its own job (isolated stacks); whichever finishes last
          # completes the turn (via all_thinking_resolved?).
          (events - deferred).each { |e| @broadcaster.resolve_thinking_for(turn:, message_id: e.id) }
          AnalyticsFillJob.perform_later(turn.id)           if analytics.any?
          AnalyzePrepareJob.perform_later(turn.id)          if analyze.any?
          ChannelDistributionFillJob.perform_later(turn.id) if distribution.any?
          AiOrchestratorJob.perform_later(turn.id)          if ai.any?
        else
          # Resolve every indicator (per-message + any orphan placeholder on a
          # zero-result turn), then complete.
          @broadcaster.resolve_thinking(turn:)
          @broadcaster.complete_turn(turn:)
        end
      end

      # Error path: surface a visible :error event in the scrollback, then resolve
      # the spinner + complete the turn. The caller re-raises so the job is marked
      # failed. Uses create_with_position! + broadcast_event (not emit) so the
      # error always lands even on a turn with no thinking indicator.
      def surface_error(turn:, detail: nil)
        event = ::Event.create_with_position!(
          conversation: @conversation, turn:, kind: :error,
          payload: { text: Pito::Copy.render("pito.copy.errors.dispatch_failed"), detail: }
        )
        @broadcaster.broadcast_event(event)
        @broadcaster.resolve_thinking(turn:)
        @broadcaster.complete_turn(turn:)
        event
      end

      # Translate a handler/dispatcher error message into an :error event payload.
      # A `pito.`-prefixed key is passed as message_key/message_args (resolved at
      # render time); anything else is already-resolved text passed as text:.
      def self.error_payload(message_key:, message_args:)
        if message_key.to_s.start_with?("pito.")
          { message_key:, message_args: }
        else
          { text: message_key }
        end
      end

      # Translate a dispatcher Result into an array of { kind:, payload: } event
      # attrs. Shared by ChatDispatchJob (async path) and
      # ChatController#handle_config (the synchronous /config path). Canonical-kind
      # assignment happens later, in #persist.
      def self.result_events(result)
        case result
        when Pito::Slash::Result::Ok, Pito::Chat::Result::Ok, Pito::Hashtag::Result::Ok
          result.events.map { |e| { kind: e[:kind], payload: e[:payload] } }
        when Pito::Slash::Result::Error, Pito::Chat::Result::Error, Pito::Hashtag::Result::Error
          [ { kind: :error, payload: error_payload(message_key: result.message_key, message_args: result.message_args) } ]
        else
          []
        end
      end

      private

      # The pre-dispatch placeholder indicator the controller emitted: the
      # lowest-position thinking event that is neither resolved nor already linked
      # to a message. nil on echo-less async turns / specs that don't pre-emit
      # one (persist then emits a fresh indicator for the first message too).
      def unresolved_unlinked_indicator(turn)
        turn.events.where(kind: :thinking).order(:position).find do |e|
          resolved = e.payload["resolved"] == true || e.payload["resolved"] == "true"
          !resolved && e.payload["for_event_id"].blank?
        end
      end

      # Link an indicator to the message it covers so resolution can target it
      # exactly. No-op when the indicator is nil (no placeholder + emit returned
      # nothing) so a message never blocks completion on a missing indicator.
      def link_indicator(indicator, to:)
        return if indicator.nil?

        indicator.update!(payload: indicator.payload.merge("for_event_id" => to.id))
      end

      # Assign canonical kinds to events handlers emit as :system.
      # First system event → :system, subsequent → :enhanced.
      # follow_up: true flag → :system_follow_up / :enhanced_follow_up.
      # Non-:system kinds (error, confirmation, enhanced, …) pass through.
      def canonical_kinds(events)
        system_indices = events.each_index.select { |i| events[i][:kind].to_s == "system" }

        events.each_with_index.map do |e, idx|
          next e unless e[:kind].to_s == "system"

          follow_up = e.dig(:payload, :follow_up) == true || e.dig(:payload, "follow_up") == true
          first     = system_indices.first == idx

          new_kind = if follow_up
            first ? :system_follow_up : :enhanced_follow_up
          else
            first ? :system : :enhanced
          end

          { kind: new_kind, payload: e[:payload] }
        end
      end
    end
  end
end
