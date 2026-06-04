# frozen_string_literal: true

module Pito
  module Stream
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
      # finishes at its own pace). The echo (always a turn's first event) opens a
      # `#turn_<id>` container appended to the scrollback; every later event in
      # the turn appends INTO that container, not at the end of the scrollback.
      def broadcast_event(event)
        html   = Pito::Stream::EventRenderer.render(event)
        helper = ApplicationController.helpers

        content =
          if event.kind == "echo"
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

        handles  = authenticated ? Channel.order(:handle).compact.map(&:at_handle) : []
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
          <div id="pito-settings" class="hidden" data-sound="#{AppSetting.sound_enabled?}" data-fx="#{AppSetting.fx_enabled?}" data-expand-all="#{AppSetting.expand_all?}"></div>
        ).html_safe

        content = helper.turbo_stream.replace("pito-settings", settings_html)

        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.uuid}",
          content:
        )
      end

      # Create and broadcast a thinking indicator for a turn.
      # The word_index is chosen once and frozen in the payload.
      def emit_thinking(turn:, dictionary:)
        words = I18n.t("pito.event.thinking.#{dictionary}.doing")
        payload = { dictionary:, word_index: rand(words.length), started_at: Time.current.iso8601 }
        emit(turn:, kind: :thinking, payload:)
      end

      # Resolve a thinking indicator: update its payload with the resolved state
      # and elapsed time (computed from the thinking's own started_at), then
      # broadcast a Turbo Stream replace.
      def resolve_thinking(turn:)
        event = turn.events.where(kind: :thinking).last
        return unless event

        started = event.payload["started_at"]
        elapsed = started ? (Time.current - Time.parse(started)).round : nil

        event.update!(
          payload: event.payload.merge(resolved: true, elapsed_seconds: elapsed)
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

      # ── Class-level global broadcasts (P54) ──────────────────────────────────

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

      # Broadcast updated #pito-settings to "pito:global" so every open tab
      # reflects the new expand-all (or sound/fx) value immediately — no reload.
      def self.broadcast_global_settings_update
        helper = ApplicationController.helpers

        settings_html = %(<div id="pito-settings" class="hidden" data-sound="#{AppSetting.sound_enabled?}" data-fx="#{AppSetting.fx_enabled?}" data-expand-all="#{AppSetting.expand_all?}"></div>).html_safe

        content = helper.turbo_stream.replace("pito-settings", settings_html)
        Turbo::StreamsChannel.broadcast_stream_to("pito:global", content:)
      rescue StandardError => e
        Rails.logger.warn("[Broadcaster] broadcast_global_settings_update failed: #{e.class}: #{e.message}")
      end

      # Mark a turn complete and broadcast the done signal that hides dots.
      def complete_turn(turn:)
        turn.update!(completed_at: Time.current)

        helper  = ApplicationController.helpers
        done_signal = %(<div data-controller="pito--done-dispatch" data-pito--done-dispatch-event-name-value="pito:done"></div>).html_safe
        content = helper.turbo_stream.append("turn_#{turn.id}", done_signal)

        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.uuid}",
          content:
        )
      end
    end
  end
end
