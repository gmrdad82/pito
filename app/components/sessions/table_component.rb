# 2026-05-18 — Beta-3 lane B candidate B7.
#
# Extracted from `app/views/settings/_security_pane.html.erb`
# (lines 39-105) — the sortable sessions table that lives inside the
# Security pane on `/settings`. Wraps the bulk-revoke toolbar, the
# sortable column headers, the per-row checkbox / user-agent cell /
# pinged cell loop, and the empty-state branch.
#
# Outside this component's surface:
#
#   * The `data-controller="sessions-bulk-revoke"` mount stays on the
#     parent `<fieldset>` in `_security_pane.html.erb` — the Stimulus
#     controller scope intentionally wraps BOTH the table (toolbar +
#     row checkboxes) AND the page-level `<dialog id=
#     "revoke_sessions_modal">` so target lookups across the table +
#     modal pair are one DOM subtree.
#   * The `<dialog id="revoke_sessions_modal">` confirm modal is a
#     separate Beta-3 candidate (B8) and stays inline at the bottom of
#     `_security_pane.html.erb` for now.
#
# Current-session detection is injected via `current_session_id:`
# instead of reading `Current.session` directly inside the component.
# This keeps the component pure-input-driven so unit specs can pin
# down the `[this]` badge + `data-current="yes"` decision against a
# fixture session set without standing up an authenticated request.
module Sessions
  class TableComponent < ViewComponent::Base
    # FB-132 (2026-05-21). Sortable column header rebuild — every data
    # column (`device`, `browser`, `ip`, `last seen`, `created`) gets a
    # `sort_link_to` and a section-accent arrow that swaps direction on
    # click. `frame:` is the Turbo Frame id wrapping the sessions
    # panel; passing it through to `sort_link_to` adds
    # `data-turbo-frame="<frame>"` + `data-turbo-action="advance"` so
    # the click navigates ONLY the frame (panel-scoped refresh) and
    # the browser URL still advances (back/forward + reload semantics
    # preserved). When `frame:` is nil the link falls back to a
    # full-page navigation — useful for plain HTML test renders that
    # don't wrap the component in a frame.
    FRAME_ID = "sessions_panel".freeze

    def initialize(sessions:, sessions_sort:, sessions_dir:, current_session_id:, frame: FRAME_ID)
      @sessions = sessions
      @sessions_sort = sessions_sort
      @sessions_dir = sessions_dir
      @current_session_id = current_session_id
      @frame = frame
    end

    attr_reader :sessions, :sessions_sort, :sessions_dir, :frame

    def current?(session)
      @current_session_id.present? && session.id == @current_session_id
    end

    def current_flag(session)
      current?(session) ? "yes" : "no"
    end

    # FB-166 (2026-05-21) — Ruby-declared focusables contract.
    #
    # Each session row is a single focusable of style `:row` (full-width
    # tint via CSS). The cursor controller reads
    # `data-tui-focusable="<key>"` + `data-tui-focusable-style="<style>"`
    # off each `<tr>`; the style drives the per-element focus visual
    # (row tint, action tint, checkbox-label tint, input border).
    #
    # FB-174 (2026-05-21) — the defaultHeader's select-all is also a
    # focusable, prepended as the FIRST entry. j from row 1 (or k from
    # the first session row) lands here so the user can keyboard-
    # toggle select-all.
    #
    # FB-PURPLE-REGRESSION (2026-05-21) — style flipped from
    # `:checkbox_label` to `:row`. The focusable moved from the single
    # `<th>` checkbox cell up to the parent `<tr>` so the focus tint
    # paints across the entire header row (matching the body-row
    # behavior). `:checkbox_label` only made sense when the focusable
    # hugged the [ ]-glyph cell; on a `<tr>` the row-wide tint is the
    # consistent visual.
    #
    # Specs assert against this method so the focus contract is locked
    # to Ruby — not scattered across HTML attributes.
    def focusables
      [ { key: "select_all", style: :row } ] +
        sessions.map { |s| { key: "row_#{s.id}", style: :row } }
    end
  end
end
