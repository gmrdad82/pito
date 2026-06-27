# frozen_string_literal: true

module Pito
  module Stream
    # Broadcaster — per-conversation Turbo Stream gateway.
    #
    # Responsible for all cable writes that originate from a single conversation.
    # Instantiated with one conversation and closed over it; never shared across
    # requests.
    #
    # Cable stream identifiers
    # ─────────────────────────
    # Per-conversation:  "pito:conversation:<uuid>"
    #   All instance-level methods write to this stream.  Subscribing clients are
    #   the browser tabs currently viewing that conversation.
    #
    # Global:            "pito:global"
    #   Class-level methods broadcast here.  Every open browser instance
    #   subscribes, allowing cross-instance UI sync (unread count, sidebar rows,
    #   settings) without a page reload.
    #
    # Turn grouping (append semantics)
    # ──────────────────────────────────
    # The echo event for a turn OPENS a `<div id="turn_<id>" class="pito-turn">`
    # container appended to `#pito-scrollback`.  Every subsequent event in the
    # same turn is appended INTO that container.  This keeps results visually
    # grouped under their prompt even when async jobs finish out-of-order.
    #
    # Instance methods
    # ─────────────────
    # emit                — validate + create Event + broadcast_event in one step.
    # broadcast_event     — broadcast an already-persisted Event (turn grouping).
    # replace_event       — Turbo Stream *replace* targeting `event_<id>`.
    # broadcast_auth_update   — replace mini-status, chatbox, and auth-gate after login.
    # broadcast_settings_update — replace #pito-settings with current AppSetting flags.
    # emit_thinking       — create + broadcast a thinking indicator for a turn.
    # resolve_thinking    — resolve a SPECIFIC indicator (thinking_event:) or ALL
    #                       unresolved indicators in a turn (turn:); broadcast replace(s).
    # resolve_thinking_for — resolve the one indicator linked to a message id
    #                       (payload["for_event_id"]); exact per-message resolve.
    # all_thinking_resolved? — true when no unresolved indicator remains in a turn
    #                       (the complete-turn gate for multi-indicator turns).
    # complete_turn       — mark turn complete + append done-dispatch signal.
    #
    # Class methods (global stream)
    # ──────────────────────────────
    # broadcast_global_mini_status         — replace #pito-mini-status on pito:global.
    # broadcast_global_conversation_row    — replace sidebar row on pito:global after rename.
    # broadcast_global_settings_update     — replace #pito-settings on pito:global.
    #
    # All class-level methods rescue StandardError and log a warning rather than
    # raising, so a cable failure never breaks the originating request.
    class Broadcaster
      def initialize(conversation:)
        @conversation = conversation
      end

      # Create an event, persist it, then immediately broadcast it.
      # Used by sync paths (auth, unauthenticated error) where persist + broadcast
      # happen together in the same controller action.
      def emit(turn:, kind:, payload:)
        Pito::Stream::EventPayload.validate!(kind:, payload:)
        event = ::Event.create_with_position!(conversation: @conversation, turn:, kind:, payload:)
        broadcast_event(event)
        event
      end

      # Broadcast an already-persisted event over the cable.
      #
      # Events are grouped by TURN so a turn's result lands directly under its
      # echo even when many commands are dispatched concurrently (each async job
      # finishes at its own pace). The FIRST event in a turn (lowest position)
      # opens a `#turn_<id>` container appended to the scrollback; every later
      # event in the turn appends INTO that container, not at the end of the
      # scrollback.
      #
      # We detect "first event" by position rather than kind so that echo-less
      # async turns (e.g. a lone :system summary from SyncVideosJob) also open
      # their container live instead of silently no-op-ing into a missing target.
      def broadcast_event(event)
        html   = Pito::Stream::EventRenderer.render(event)
        helper = ApplicationController.helpers

        opens_container = event.turn.events.where("position < ?", event.position).none?

        content =
          if opens_container
            helper.turbo_stream.append(
              "pito-scrollback",
              %(<div id="turn_#{event.turn_id}" class="pito-turn">#{html}</div>).html_safe
            )
          else
            helper.turbo_stream.append("turn_#{event.turn_id}", html)
          end

        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.uuid}",
          content:
        )
        event
      end

      # Replace the chatbox conversation-name slot live (rename / Unnamed→named).
      # `title` is the display name when named, or nil to clear it. Broadcasts to
      # the conversation's stream so the open chatbox reflects the new name
      # without a reload.
      def broadcast_conversation_name(title:)
        slot_html = ApplicationController.renderer.render(
          Pito::Shell::Chatbox::NameComponent.new(title:),
          layout: false
        ).html_safe
        content = ApplicationController.helpers.turbo_stream.replace(
          Pito::Shell::Chatbox::NameComponent::SLOT_ID, slot_html
        )
        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.uuid}",
          content:
        )
      end

      # Replace an already-persisted event in-place via Turbo Stream.
      # The event's segment must have been rendered with id: "event_#{event.id}".
      # Used by confirmation routing to flip a segment to processing/resolved state.
      def replace_event(event)
        html    = Pito::Stream::EventRenderer.render(event)
        helper  = ApplicationController.helpers
        content = helper.turbo_stream.replace("event_#{event.id}", html)
        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.uuid}",
          content:
        )
        event
      end

      # Consume every prior LIVE repliable event in the conversation (turns strictly
      # earlier than `before_turn`) so old `#handle` affordances retire the moment a
      # new message renders — only the newest turn's handles stay live. Stamps
      # `reply_consumed: true` + replace_event to re-render. Shared by the Finalizer
      # (any new :system/:confirmation turn) so new chat verbs AND replies-that-append
      # both retire prior hashtags uniformly.
      def consume_prior_live_replies(before_turn:)
        @conversation.events
          .where("turn_id < ?", before_turn.id)
          .where("payload->>'reply_handle' IS NOT NULL")
          .where("(payload->>'reply_consumed') IS NULL OR (payload->>'reply_consumed') = 'false'")
          .find_each do |event|
            event.update!(payload: event.payload.merge("reply_consumed" => true))
            replace_event(event)
          end
      end

      # Broadcast Turbo Stream replacements for the mini status bar and chatbox
      # after an auth state change (/login success). Both elements carry stable
      # DOM ids so the replace lands on the right targets.
      def broadcast_auth_update(authenticated:, channel: "@all", period: "7d")
        helper = ApplicationController.helpers

        mini_status_html = ApplicationController.renderer.render(
          Pito::Shell::MiniStatusComponent.new(
            mode: :connection, state: authenticated,
            notifications: Notification.unread.count, show_notifications: true
          ),
          layout: false
        )
        mini_status_wrapper = %(<div id="pito-mini-status" data-pito--home-transition-target="miniStatusSlide" style="margin-left: auto;">#{mini_status_html}</div>).html_safe

        handles  = authenticated ? ::Channel.order(:handle).compact.map(&:at_handle) : []
        channels = authenticated ? ([ "@all" ] + handles) : nil
        filter   = authenticated ? {
          channel: handles.any? ? "@all" : "none",
          period:,
          channels: handles.any? ? ([ "@all" ] + handles) : []
        } : nil

        chatbox_html = ApplicationController.renderer.render(
          Pito::Shell::ChatboxComponent.new(
            state:        :default,
            authenticated:,
            filter:,
            input_data:   { pito__chat_form_target: "inputField" }
          ),
          layout: false
        ).html_safe

        auth_gate_html = %(<div id="pito-auth-gate" class="hidden" data-authenticated="#{authenticated}"></div>).html_safe

        content = [
          helper.turbo_stream.replace("pito-mini-status", mini_status_wrapper),
          helper.turbo_stream.replace("pito-chatbox", chatbox_html),
          helper.turbo_stream.replace("pito-auth-gate", auth_gate_html)
        ].join

        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.uuid}",
          content:
        )
      end

      # Broadcast a Turbo Stream replacement for #pito-settings after a
      # sound/fx toggle. The element carries the current flag values as
      # data attributes so the JS audio controller can react immediately.
      def broadcast_settings_update
        helper = ApplicationController.helpers

        settings_html = %(
          <div id="pito-settings" class="hidden" data-sound="#{AppSetting.sound_enabled?}" data-fx="#{AppSetting.fx_enabled?}" data-fx-effect="#{AppSetting.fx_effect}" data-theme="#{AppSetting.theme}"></div>
        ).html_safe

        content = helper.turbo_stream.replace("pito-settings", settings_html)

        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.uuid}",
          content:
        )
      end

      # Create and broadcast a thinking indicator for a turn.
      # `order` is a shuffled list of indices into the dictionary's `doing` array;
      # the client cycles through it (one verb per INTERVAL_SECONDS) and the
      # resolve step picks the same final index from elapsed time, so the
      # past-tense word matches the last verb shown.
      def emit_thinking(turn:, dictionary:)
        words   = I18n.t("pito.copy.thinking.#{dictionary}.doing")
        order   = (0...Array(words).length).to_a.shuffle
        payload = { dictionary:, order:, started_at: Time.current.iso8601 }
        emit(turn:, kind: :thinking, payload:)
      end

      # Resolve thinking indicator(s). Two modes:
      #
      #   resolve_thinking(thinking_event:)  — resolve ONE specific indicator
      #     (exact, used by the per-message resolve so multiple indicators in the
      #     same turn never resolve the wrong one).
      #   resolve_thinking(turn:)            — resolve EVERY still-unresolved
      #     indicator in the turn (turn-level convenience for the sync/error paths
      #     and single-indicator async jobs).
      #
      # Each resolve computes elapsed time from the indicator's OWN started_at and
      # broadcasts a Turbo Stream replace targeting that indicator's segment.
      def resolve_thinking(turn: nil, thinking_event: nil)
        if thinking_event
          resolve_one(thinking_event)
        elsif turn
          turn.events.where(kind: :thinking).order(:position).each do |event|
            resolve_one(event) unless thinking_resolved?(event)
          end
          nil
        end
      end

      # Resolve the single indicator linked to `message_id` via its payload
      # `for_event_id` (set by the Finalizer when it persists the message). No-op
      # when none is found or it's already resolved. The exact per-message path.
      def resolve_thinking_for(turn:, message_id:)
        event = turn.events.where(kind: :thinking).find do |e|
          e.payload["for_event_id"].to_s == message_id.to_s
        end
        return unless event
        return event if thinking_resolved?(event)

        resolve_one(event)
      end

      # True when no still-spinning indicator remains in the turn. The gate for
      # completing a turn that carries multiple per-message indicators: complete
      # only once EVERY indicator (ready + analytics-pending) is resolved.
      def all_thinking_resolved?(turn:)
        turn.events
          .where(kind: :thinking)
          .where("(payload->>'resolved') IS DISTINCT FROM 'true'")
          .none?
      end

      private

      def thinking_resolved?(event)
        event.payload["resolved"] == true || event.payload["resolved"] == "true"
      end

      # Stamp a single thinking indicator resolved (elapsed from its OWN
      # started_at) and broadcast a Turbo Stream replace for its segment.
      def resolve_one(event)
        started = event.payload["started_at"]
        elapsed = started ? (Time.current - Time.parse(started)) : nil

        order      = event.payload["order"].presence || [ event.payload["word_index"].to_i ]
        word_index = Pito::Event::ThinkingComponent.word_index_at(order:, elapsed_seconds: elapsed || 0)

        event.update!(
          payload: event.payload.merge(resolved: true, elapsed_seconds: elapsed, word_index:)
        )

        html    = Pito::Stream::EventRenderer.render(event)
        helper  = ApplicationController.helpers
        content = helper.turbo_stream.replace("event_#{event.id}", html)

        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.uuid}",
          content:
        )
        event
      end

      public

      # ── Class-level global broadcasts ────────────────────────────────────────

      # Broadcast the current mini-status HTML (unread count + auth state) to
      # the "pito:global" stream so every open browser instance updates its
      # unread count without a page reload. Called after a notification is
      # toggled read/unread so the count syncs cross-instance.
      def self.broadcast_global_mini_status
        helper = ApplicationController.helpers

        mini_status_html = ApplicationController.renderer.render(
          Pito::Shell::MiniStatusComponent.new(
            mode: :connection, state: true,
            notifications: Notification.unread.count, show_notifications: true
          ),
          layout: false
        )
        mini_status_wrapper = %(<div id="pito-mini-status" data-pito--home-transition-target="miniStatusSlide" style="margin-left: auto;">#{mini_status_html}</div>).html_safe

        content = helper.turbo_stream.replace("pito-mini-status", mini_status_wrapper)
        Turbo::StreamsChannel.broadcast_stream_to("pito:global", content:)
      rescue StandardError => e
        Rails.logger.warn("[Broadcaster] broadcast_global_mini_status failed: #{e.class}: #{e.message}")
      end

      # Broadcast a conversation row replacement to "pito:global" so that any
      # open sidebar on other instances updates when a conversation is renamed.
      def self.broadcast_global_conversation_row(conversation:)
        helper = ApplicationController.helpers

        timestamp = Pito::Formatter::CompactTimeAgo.call(
          conversation.events.maximum(:created_at) || conversation.created_at
        )

        row_html = ApplicationController.renderer.render(
          partial: "conversations/row",
          locals: { conversation:, current: false, timestamp: }
        )

        content = helper.turbo_stream.replace("conversation_row_#{conversation.uuid}", row_html)
        Turbo::StreamsChannel.broadcast_stream_to("pito:global", content:)
      rescue StandardError => e
        Rails.logger.warn("[Broadcaster] broadcast_global_conversation_row failed: #{e.class}: #{e.message}")
      end

      # Remove a conversation's sidebar row everywhere (pito:global) — used when an
      # async DeleteConversationJob finishes destroying the record. Takes the uuid
      # because the record is already gone by then.
      def self.broadcast_global_conversation_row_removed(uuid:)
        content = ApplicationController.helpers.turbo_stream.remove("conversation_row_#{uuid}")
        Turbo::StreamsChannel.broadcast_stream_to("pito:global", content:)
      rescue StandardError => e
        Rails.logger.warn("[Broadcaster] broadcast_global_conversation_row_removed failed: #{e.class}: #{e.message}")
      end

      # Broadcast updated #pito-settings to "pito:global" so every open tab
      # reflects the new sound/fx value immediately — no reload.
      def self.broadcast_global_settings_update
        helper = ApplicationController.helpers

        settings_html = %(<div id="pito-settings" class="hidden" data-sound="#{AppSetting.sound_enabled?}" data-fx="#{AppSetting.fx_enabled?}" data-fx-effect="#{AppSetting.fx_effect}" data-theme="#{AppSetting.theme}"></div>).html_safe

        content = helper.turbo_stream.replace("pito-settings", settings_html)
        Turbo::StreamsChannel.broadcast_stream_to("pito:global", content:)
      rescue StandardError => e
        Rails.logger.warn("[Broadcaster] broadcast_global_settings_update failed: #{e.class}: #{e.message}")
      end

      # Broadcast a custom `set-theme` Turbo Stream action to "pito:global" so that
      # every open browser tab recolors immediately when a theme is applied or
      # previewed via the `/themes` command. The action reads the `theme` attribute
      # from the stream element and sets `document.documentElement.dataset.theme`.
      #
      # apply persists THEN broadcasts; preview broadcasts only; reset persists
      # the default THEN broadcasts.
      def self.broadcast_global_theme(slug)
        content = %(<turbo-stream action="set-theme" theme="#{slug}"></turbo-stream>)
        Turbo::StreamsChannel.broadcast_stream_to("pito:global", content:)
      rescue StandardError => e
        Rails.logger.warn("[Broadcaster] broadcast_global_theme failed: #{e.class}: #{e.message}")
      end

      # Broadcast the notifications sidebar into #pito-sidebar over the
      # conversation's cable stream.  Called by the /notifications slash handler
      # so the panel opens from the chat input, mirroring Ctrl+/.
      #
      # Renders app/views/notifications/_panel.html.erb (the same partial that
      # NotificationsController#index uses) so no markup is ever duplicated.
      def broadcast_notifications_sidebar
        helper        = ApplicationController.helpers
        notifications = Notification.panel_ordered

        panel_html = ApplicationController.renderer.render(
          partial: "notifications/panel",
          locals:  { notifications: }
        )

        content = helper.turbo_stream.update("pito-sidebar", panel_html.html_safe)

        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.uuid}",
          content:
        )
      end

      # Broadcast a Turbo Stream `replace` for a single import step row inside
      # #pito-sidebar.  The JS pre-renders 5 shimmer rows with ids
      # `import-step-1` through `import-step-5`; this method replaces each row
      # as the job completes the corresponding step.
      #
      # When done: true the step label renders with a checkmark and no shimmer.
      # When done: false (error) it renders with an error indicator.
      def broadcast_import_step(step:, label:, done: true)
        dot_html =
          if done
            %(<span class="text-accent shrink-0">✓</span>)
          else
            ApplicationController.renderer.render(
              Pito::Shell::ShimmerTextComponent.new(text: "●", extra_classes: "shrink-0"),
              layout: false
            ).strip
          end

        row_html = <<~HTML.html_safe
          <div id="import-step-#{step}" class="flex items-center gap-2 py-1 px-2">
            #{dot_html}
            <span class="#{done ? "text-fg" : "text-fg-dim"}">#{ERB::Util.html_escape(label)}</span>
          </div>
        HTML

        helper  = ApplicationController.helpers
        content = helper.turbo_stream.replace("import-step-#{step}", row_html)

        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.uuid}",
          content:
        )
      end

      # Mark a turn complete and broadcast the done signal that hides dots.
      def complete_turn(turn:)
        turn.update!(completed_at: Time.current)
        broadcast_done(dom_id: "turn_#{turn.id}")
      end

      # Broadcast the done signal (hides the post-command dots) appended to an
      # arbitrary stable DOM id — used by turn-less flows such as :mutate
      # follow-ups, where the work targets an existing event rather than a turn.
      # The pito--done-dispatch controller fires `pito:done` on connect; the
      # element is ephemeral (cleared when the target is next replaced).
      def broadcast_done(dom_id:)
        done_signal = %(<div data-controller="pito--done-dispatch" data-pito--done-dispatch-event-name-value="pito:done"></div>).html_safe
        content     = ApplicationController.helpers.turbo_stream.append(dom_id, done_signal)

        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.uuid}",
          content:
        )
      end
    end
  end
end
