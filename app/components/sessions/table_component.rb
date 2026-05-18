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
    def initialize(sessions:, sessions_sort:, sessions_dir:, current_session_id:)
      @sessions = sessions
      @sessions_sort = sessions_sort
      @sessions_dir = sessions_dir
      @current_session_id = current_session_id
    end

    attr_reader :sessions, :sessions_sort, :sessions_dir

    def current?(session)
      @current_session_id.present? && session.id == @current_session_id
    end

    def current_flag(session)
      current?(session) ? "yes" : "no"
    end
  end
end
