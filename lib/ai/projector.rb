# frozen_string_literal: true

module Ai
  # Deterministic payload → text projection of ONE anchored event — the
  # owner's core ask for the anchored `#<handle> @ai <question>` reply: the
  # REAL content the owner is pointing at must reach the model as a clean
  # projection, never raw jsonb and never a lossy history accident.
  #
  # Reuses Pito::Mcp::EventText — the SAME chrome-free projector MCP clients
  # and Ai::History (assistant_message) already read: intro/body text with
  # HTML stripped to plain, table headers + row cell TEXTS, kv-shaped detail
  # copy (everything a rendered ViewComponent card carries lives only in its
  # `body`, so the HTML→text fallback covers it), breakdown lists. None of
  # it ever touches CSS classes, prefill/data attributes, reply handles, or
  # other chrome — EventText never reads those payload keys in the first
  # place. So this is a thin wrapper, not a second projection engine.
  #
  # An :ai answer's payload ("blocks", not table_rows/body) projects BLANK
  # through EventText — #call then returns nil for it, which is exactly
  # right: an :ai anchor keeps TODAY's behavior (AiOrchestratorJob#anchor_turn
  # + Ai::History's must_include_turn already carry that exchange in full;
  # see the job's class header) rather than duplicating it here. No special
  # case needed — the shape simply doesn't match anything EventText projects.
  module Projector
    module_function

    # @param event [Event, nil] the anchored event (any kind, any reply_target).
    # @return [String, nil] the projection, or nil when there is nothing to show.
    def call(event)
      return nil unless event

      text = Pito::Mcp::EventText.call([ { kind: event.kind, payload: event.payload } ]).to_s.strip
      return nil if text.blank?

      origin = event.payload["origin_tool"].presence
      origin ? "#{text}\n\n(from the `#{origin}` command)" : text
    end
  end
end
