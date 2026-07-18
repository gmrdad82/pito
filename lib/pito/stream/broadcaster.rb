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

      # Kinds whose events are stamped with a reply_handle (if absent) so that
      # the universal share/revoke/unshare tools work on any :system/:enhanced/:confirmation
      # message regardless of its reply_target.
      HANDLE_STAMPING_KINDS = %w[system enhanced confirmation].freeze

      # Create an event, persist it, then immediately broadcast it.
      # Used by sync paths (auth, unauthenticated error) where persist + broadcast
      # happen together in the same controller action.
      def emit(turn:, kind:, payload:)
        Pito::Stream::EventPayload.validate!(kind:, payload:)
        if HANDLE_STAMPING_KINDS.include?(kind.to_s)
          # Honor a per-tool `universal_reply: false` opt-out (tools.yml): stamp
          # the origin tool so later gates agree, and withhold the universal-only
          # handle when nothing could ever act on it — opted-out tool OR a kind
          # the universal_reply.share `kinds:` list doesn't cover (see
          # Pito::FollowUp.actions_possible? — the owner's "no actions → no
          # handle" rule).
          origin_tool = Pito::Dispatch::UniversalReply.origin_tool(turn)
          payload["origin_tool"] = origin_tool if origin_tool && !payload.frozen?
          Pito::FollowUp.ensure_handle!(payload, conversation: @conversation, kind:)
        end
        # (The living-background fx stamp lives in Event.create_with_position!
        # — the ONE create door every path shares; see app/models/event.rb.)
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
        # Anything reaching the scrollback invalidates the L2 snapshot — the
        # next page load reassembles from L1 fragments.
        Pito::Stream::ScrollbackCache.bust(@conversation)

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
        broadcast_json(type: "event.append", event:)
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
        Pito::Stream::ScrollbackCache.bust(@conversation)

        # Re-derive the fx stamp (F2): a replace-style follow-up may have
        # changed what the message IS (columns added, similars joined) — the
        # mood must track the content it replaces.
        if Pito::Fx::Context.eligible?(event.kind)
          fx = Pito::Fx::Context.derive(kind: event.kind, payload: event.payload)
          if fx != event.payload["fx"]
            event.payload = fx ? event.payload.merge("fx" => fx) : event.payload.except("fx")
            event.save!
          end
        end

        html    = Pito::Stream::EventRenderer.render(event)
        helper  = ApplicationController.helpers
        content = helper.turbo_stream.replace("event_#{event.id}", html)
        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.uuid}",
          content:
        )
        broadcast_json(type: "event.replace", event:)
        event
      end

      # Narrate the AI orchestrator's live tool activity inside a pending :ai
      # event — replaces the message's `event_<id>__ai_status` slot (rendered by
      # Pito::Event::AiComponent while status is "pending"). EPHEMERAL chrome:
      # never persisted — the final replace_event carries the real payload
      # (mirrors the replace_metric_fragment pattern). Also mirrored onto the
      # JSON stream as `event.ai_status` (see broadcast_ai_status) — additive,
      # alongside this Turbo replace, never instead of it.
      # Stream ONE cut block into a pending :ai event's blocks container —
      # ephemeral preview chrome (never persisted): the final replace_event
      # re-renders the whole message from the persisted payload, replacing
      # everything streamed here. Also mirrored onto the JSON stream as
      # `event.ai_block` — additive, alongside the Turbo upsert below, never
      # instead of it.
      #
      # UPSERT, not append: a kv_table/table block is re-broadcast repeatedly at
      # the same `index` as its rows stream in (partial snapshots), then once
      # more in final form — each delivery must REPLACE the prior preview div
      # rather than pile up duplicates. We remove the existing
      # `event_<id>__ai_block_<index>` div then append the freshly rendered one,
      # both folded into a SINGLE broadcast (one cable transmission). `remove`
      # on a not-yet-rendered id is a client-side no-op, so a first-time index
      # still appends cleanly in order; a repeat index re-appends at the end,
      # which is order-safe because the block currently streaming is always the
      # last one in the slot.
      def broadcast_ai_block(event:, block:, index:)
        component = Pito::Event::Ai::BlockRenderer.component_for(block)
        html      = ApplicationController.renderer.render(component, layout: false)
        dom_id    = "event_#{event.id}__ai_block_#{index}"
        wrapped   = %(<div id="#{dom_id}">#{html}</div>).html_safe
        helper    = ApplicationController.helpers
        content   = helper.turbo_stream.remove(dom_id) +
                    helper.turbo_stream.append("event_#{event.id}__ai_blocks", wrapped)
        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.uuid}",
          content:
        )

        # JSON pane of the same tick (pito-tui et al.) — additive only, same
        # stream broadcast_json uses. Unknown types are ignored by the web by
        # design; the final event.replace stays authoritative (crash-safe).
        ActionCable.server.broadcast(
          "pito:json:conversation:#{@conversation.uuid}",
          { type: "event.ai_block", event_id: event.id, index:, block: }
        )
        nil
      end

      def broadcast_ai_status(event:, text:)
        helper  = ApplicationController.helpers
        slot    = "event_#{event.id}__ai_status"
        # pito-network-shimmer — the same live sweep the Thinking block's copy
        # wears; this line is the same kind of "working on it" chrome.
        content = helper.turbo_stream.replace(
          slot,
          %(<div id="#{slot}" class="text-fg-faded pito-network-shimmer">#{ERB::Util.html_escape(text)}</div>).html_safe
        )
        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.uuid}",
          content:
        )

        # JSON pane of the same tick — additive only (see broadcast_ai_block).
        # Unknown types are ignored by the web by design; the final
        # event.replace stays authoritative (crash-safe).
        ActionCable.server.broadcast(
          "pito:json:conversation:#{@conversation.uuid}",
          { type: "event.ai_status", event_id: event.id, text: }
        )
        nil
      end

      # Replace a SINGLE metric's cell inside a live glance message — targets the
      # message's `<token>__metric_<key>` dom-id (set by MetricCellComponent) so each
      # metric swaps in independently as its dedicated per-metric job lands
      # (progressive at-a-glance), without re-rendering the whole message. `html` is
      # the rendered MetricCellComponent for that key (same id, so the swap lands).
      def replace_metric_fragment(token:, key:, html:)
        helper  = ApplicationController.helpers
        content = helper.turbo_stream.replace("#{token}__metric_#{key}", html)
        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.uuid}",
          content:
        )
        nil
      end

      # Consume every prior LIVE repliable event in the conversation (turns strictly
      # earlier than `before_turn`) so old `#handle` affordances retire the moment a
      # new message renders — only the newest turn's handles stay live. Stamps
      # `reply_consumed: true` + replace_event to re-render. Shared by the Finalizer
      # (any new :system/:confirmation turn) so new chat tools AND replies-that-append
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
          <div id="pito-settings" class="hidden" data-sound="#{AppSetting.sound_enabled?}" data-theme="#{AppSetting.theme}"></div>
        ).html_safe

        content = helper.turbo_stream.replace("pito-settings", settings_html)

        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.uuid}",
          content:
        )
      end

      # Create and broadcast a thinking indicator for a turn.
      # `order` is a shuffled list of indices into the dictionary's `doing` array;
      # the client cycles through it (one tool per INTERVAL_SECONDS) and the
      # resolve step picks the same final index from elapsed time, so the
      # past-tense word matches the last tool shown.
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
      # Busts the L2 snapshot: the resolve mutates the payload and broadcasts
      # directly (not via replace_event), so without this a reload captured
      # between the message broadcast and the resolve would freeze an
      # unresolved spinner into the snapshot.
      def resolve_one(event)
        Pito::Stream::ScrollbackCache.bust(@conversation)
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
        broadcast_json(type: "event.replace", event:)
        event
      end

      # Mirror a persisted-event broadcast onto the conversation's JSON stream
      # (Pito::JsonChannel — pito-tui and any future non-browser client).
      # Called from ALL THREE choke points that broadcast persisted events
      # (broadcast_event, replace_event, resolve_one) and from nowhere else:
      # the Broadcaster stays the single scrollback door — this is its second
      # pane, not a second door. Ephemeral chrome (meter, auth, sidebars,
      # metric fragments, done-div) is deliberately NOT mirrored.
      def broadcast_json(type:, event:)
        ActionCable.server.broadcast(
          "pito:json:conversation:#{@conversation.uuid}",
          { type:, event: Pito::Stream::EventJson.call(event) }
        )
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

        settings_html = %(<div id="pito-settings" class="hidden" data-sound="#{AppSetting.sound_enabled?}" data-theme="#{AppSetting.theme}"></div>).html_safe

        content = helper.turbo_stream.replace("pito-settings", settings_html)
        Turbo::StreamsChannel.broadcast_stream_to("pito:global", content:)
      rescue StandardError => e
        Rails.logger.warn("[Broadcaster] broadcast_global_settings_update failed: #{e.class}: #{e.message}")
      end

      # The version HEARTBEAT: replace the hidden #pito-server-version
      # node on pito:global with the running build's identity. Broadcast every
      # 5 minutes by VersionHeartbeatJob — a RECURRING push is race-proof where
      # a boot-time broadcast is not (clients reconnect on their own schedule
      # after an update kills the old container's sockets; whoever missed one
      # tick catches the next). Client side, pito--version-watch remounts on
      # every replace and compares against the page's build → refresh nudge.
      def self.broadcast_global_version
        helper = ApplicationController.helpers

        version_html = %(<div id="pito-server-version" class="hidden" data-controller="pito--version-watch" data-pito--version-watch-version-value="#{ERB::Util.html_escape(Pito::Version.suffix)}"></div>).html_safe

        content = helper.turbo_stream.replace("pito-server-version", version_html)
        Turbo::StreamsChannel.broadcast_stream_to("pito:global", content:)
      rescue StandardError => e
        Rails.logger.warn("[Broadcaster] broadcast_global_version failed: #{e.class}: #{e.message}")
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
        helper                     = ApplicationController.helpers
        notifications, next_cursor = Notification.panel_page

        panel_html = ApplicationController.renderer.render(
          partial: "notifications/panel",
          locals:  { notifications:, next_cursor: }
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

      # Broadcast a Turbo Stream replace for the context meter (#pito-context-meter)
      # after each turn, so the fill % updates as messages accumulate.
      # Called from ChatDispatchJob after broadcast_showcase.
      #
      # Carries the conversation NAME too — this replaces the WHOLE meter, and
      # rendering it nameless wiped a just-renamed title on the next counter
      # tick ("saw it for a bit, then it disappeared").
      def broadcast_context_meter
        event_count = @conversation.context_event_count
        html = ApplicationController.renderer.render(
          Pito::Shell::ContextMeterComponent.new(
            event_count:,
            conversation_name: (@conversation.named? ? @conversation.display_name : nil)
          ),
          layout: false
        ).html_safe
        content = ApplicationController.helpers.turbo_stream.replace("pito-context-meter", html)
        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.uuid}",
          content:
        )

        # The JSON pane of the same tick — non-browser clients get a
        # conversation.update whenever the web meter refreshes (identical
        # trigger, identical numbers). Unread rides along so the TUI's mini
        # status stays current without polling. Unknown types/fields are
        # ignored by design on the client, so this is additive.
        ActionCable.server.broadcast(
          "pito:json:conversation:#{@conversation.uuid}",
          {
            type: "conversation.update",
            context: {
              pct:       Pito::Shell::ContextMeterComponent.pct(event_count),
              count:     event_count,
              threshold: Pito::Shell::ContextMeterComponent::THRESHOLD
            },
            notifications: { unread: Notification.unread.count }
          }
        )
      rescue StandardError => e
        Rails.logger.warn("[Broadcaster] broadcast_context_meter failed: #{e.class}: #{e.message}")
      end

      # Broadcast a new hint set (10–15 command strings) to the chatbox so the
      # pito--placeholder-rotate Stimulus controller can cycle them through the
      # field's native placeholder. Targets the stable `#pito-showcase-data`
      # element embedded in the chatbox; the replace swaps out its JSON content so
      # the controller sees the update via a MutationObserver (no full chatbox
      # re-render needed). The replacement MUST keep the controller's target attr
      # so Stimulus re-registers the new node as the `data` target.
      def broadcast_showcase(suggestions:)
        json = Pito::Showcase::SafeJson.encode(Array(suggestions))
        html = %(<script type="application/json" id="pito-showcase-data" data-pito--placeholder-rotate-target="data">#{json}</script>).html_safe
        content = ApplicationController.helpers.turbo_stream.replace("pito-showcase-data", html)
        Turbo::StreamsChannel.broadcast_stream_to(
          "pito:conversation:#{@conversation.uuid}",
          content:
        )
      rescue StandardError => e
        Rails.logger.warn("[Broadcaster] broadcast_showcase failed: #{e.class}: #{e.message}")
      end

      # Mark a turn complete and broadcast the done signal that hides dots.
      def complete_turn(turn:)
        turn.update!(completed_at: Time.current)
        # Conversation search (3.0.0) — embed the turn's events in the background
        # now that they're final.
        EventEmbedJob.perform_later(turn.id)
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
