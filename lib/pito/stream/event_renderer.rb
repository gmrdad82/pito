# frozen_string_literal: true

module Pito
  module Stream
    # EventRenderer — factory that maps an Event to its ViewComponent and renders it.
    #
    # COMPONENT_CLASSES is a frozen Hash<String, Class> mapping each event `kind`
    # string to its ViewComponent class:
    #
    #   "echo"                   → Pito::Event::EchoComponent
    #   "thinking"               → Pito::Event::ThinkingComponent
    #   "system"                 → Pito::Event::SystemComponent
    #   "enhanced"               → Pito::Event::EnhancedComponent
    #   "system_follow_up"       → Pito::Event::SystemFollowUpComponent
    #   "enhanced_follow_up"     → Pito::Event::EnhancedFollowUpComponent
    #   "confirmation"           → Pito::Event::ConfirmationComponent
    #   "confirmation_follow_up" → Pito::Event::ConfirmationFollowUpComponent
    #   "error"                  → Pito::Event::ErrorComponent
    #
    # Public API (all class methods)
    # ────────────────────────────────
    # render(event)                           — renders the event to an HTML string.
    # component_for(event)                    — instantiate the component without rendering.
    # build_component(kind, payload, event:)  — lower-level; caller supplies kind + payload.
    #
    # Payload coercion
    # ─────────────────
    # `indifferent_payload` converts `event.payload` to a
    # HashWithIndifferentAccess so components can access keys by either
    # String or Symbol.  Non-Hash payloads are passed through unchanged.
    #
    # Unknown kind
    # ─────────────
    # `build_component` calls `Hash#fetch` with a block that raises
    # `ArgumentError` ("No component registered for event kind: <kind>").
    # Callers that need a safe path should rescue ArgumentError.
    class EventRenderer
      COMPONENT_CLASSES = {
        "echo"                    => Pito::Event::EchoComponent,
        "thinking"                => Pito::Event::ThinkingComponent,
        "system"                  => Pito::Event::SystemComponent,
        "enhanced"                => Pito::Event::EnhancedComponent,
        "system_follow_up"        => Pito::Event::SystemFollowUpComponent,
        "enhanced_follow_up"      => Pito::Event::EnhancedFollowUpComponent,
        "confirmation"            => Pito::Event::ConfirmationComponent,
        "confirmation_follow_up"  => Pito::Event::ConfirmationFollowUpComponent,
        "error"                   => Pito::Event::ErrorComponent,
        "theme_diff"              => Pito::Event::ThemeDiffComponent
      }.freeze

      # Renders an event to HTML: fragment-cached body (L1 — FragmentCache) +
      # the serve-time meta-slot fill. The fragment carries a
      # `data-pito-meta-slot` div instead of the handle/channel meta line;
      # the CURRENT meta state (handle liveness included) renders into it here,
      # so handle consumption never invalidates a cached fragment.
      def self.render(event)
        html = Pito::Stream::FragmentCache.fetch(event) do
          ApplicationController.renderer.render(component_for(event), layout: false)
        end
        fill_meta_slot(html, event)
      end

      # The public (share-page) render: reply affordances suppressed, fragment
      # cache bypassed (share pages get their own page-level cache — Phase 7).
      def self.render_public(event)
        html = ApplicationController.renderer.render(
          component_for(event, suppress_reply: true), layout: false
        )
        fill_meta_slot(html, event, suppress_reply: true)
      end

      META_SLOT = "<div data-pito-meta-slot></div>"

      def self.fill_meta_slot(html, event, suppress_reply: false)
        return html unless html.include?("data-pito-meta-slot")

        component = component_for(event, suppress_reply:)
        return html.sub(META_SLOT, "") unless component.respond_to?(:meta_handle)

        handle  = component.meta_handle
        channel = component.channel
        meta =
          if handle || channel.present?
            ApplicationController.renderer.render(
              Pito::Event::MetaLineComponent.new(handle:, channel:), layout: false
            )
          else
            ""
          end
        html.sub(META_SLOT, meta)
      end

      # @param suppress_reply [Boolean] when true, strip the reply affordances
      #   (reply_handle / reply_target) from the payload so the rendered message
      #   shows NO `#handle` and isn't presented as repliable. Used by the public
      #   /share/:uuid page — a shared message is read-only, so its hashtag must not
      #   appear (owner 2026-07-01). Components read reply_handle from the PAYLOAD,
      #   so removing it here is enough.
      def self.component_for(event, suppress_reply: false)
        payload = indifferent_payload(event)
        payload = payload.except("reply_handle", "reply_target") if suppress_reply && payload.is_a?(Hash)
        build_component(event.kind, payload, event:)
      end

      def self.build_component(kind, payload, event: nil)
        component_class = COMPONENT_CLASSES.fetch(kind.to_s) do
          raise ArgumentError, "No component registered for event kind: #{kind.inspect}"
        end
        component_class.new(payload:, event:)
      end

      def self.indifferent_payload(event)
        event.payload.is_a?(Hash) ? event.payload.with_indifferent_access : event.payload
      end
    end
  end
end
