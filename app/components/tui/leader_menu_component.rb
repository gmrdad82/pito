module Tui
  # Beta 4 — D5 (2026-05-22). 1-level shallow leader menu.
  #
  # SPACE in NORMAL mode opens a which-key style popup listing the
  # supported leader actions. The user types a single next-key (`h`,
  # `v`, `g`, `?`, `:`, `q`, `a`) → action fires → dialog closes.
  # Esc closes. This is the clean rebuild after the 1700-line nested-
  # submenu / flat-key / compact-mode prior controller was deemed
  # spaghetti; nesting is gone, prefix-accumulator is gone, page-actions
  # are gone. One-keystroke commit, always.
  #
  # Chrome flows through `Tui::DialogComponent` so the title-in-border,
  # `[Esc] to close` hint, backdrop-click guard, screen accent, and
  # zero-radius hairline border all stay consistent with help / about /
  # confirmation dialogs.
  #
  # Entries are a class constant (DEFAULT_ENTRIES) ordered as locked in
  # plan D5. Each row is rendered via `Tui::LeaderMenuEntryComponent`.
  # An entry carries either `path:` (Turbo navigation) OR `action_name:`
  # (a registered `Pito::Action` symbol dispatched through
  # `window.Pito.dispatchAction`) OR `dispatch_method:` (an arbitrary
  # `pito:leader:<method>` CustomEvent surfaced for layout-mounted
  # listeners like the help/about dialog openers). The Stimulus
  # controller reads these per-entry data attrs and resolves at
  # keystroke time.
  #
  # Kwargs:
  #   entries:       Optional override of the entries Array. Defaults to
  #                  DEFAULT_ENTRIES. Each entry is a Hash with keys
  #                  `:key` (String, the next-key character), `:label`
  #                  (String, i18n-resolved row label) and EXACTLY ONE
  #                  of `:path` / `:action_name` / `:dispatch_method`.
  #   screen_accent: Symbol section accent (`:home`/`:videos`/`:games`/
  #                  `:settings`). Defaults to `:home`. The
  #                  DialogComponent paints border + title in this
  #                  accent when `[open]`.
  #
  # DOM id is locked to `tui-leader-menu` — the Stimulus controller and
  # the bottom-status-bar `[_]` action both target this id.
  class LeaderMenuComponent < ViewComponent::Base
    DIALOG_ID = "tui-leader-menu".freeze

    # 2026-05-24 — `s` entry added: `Space s` toggles TST sync. The
    # entry fires the `:toggle_tst_sync` registered action which flips
    # the master sync switch (one flag covers every screen). The TST
    # sync indicator reads and persists state server-side via
    # `Pito::SyncState.pause_master!` / `resume_master!`.
    #
    # 2026-05-25 (collapse-to-master) — `p` entry: `Space p` triggers
    # `:toggle_master_sync` for the master sync indicator. Only the
    # master TST `[ ] sync` indicator exists; per-panel sync indicators
    # have been removed. dispatch_method resolves via the
    # `tui:leader:toggle_pause` custom event which the
    # tui_sync_indicator_controller intercepts.
    DEFAULT_ENTRIES = [
      { key: "h", label_key: "tui.leader.entries.h.label",       path: "/" },
      { key: "v", label_key: "tui.leader.entries.v.label",       path: "/videos" },
      { key: "g", label_key: "tui.leader.entries.g.label",       path: "/games" },
      { key: "s", label_key: "tui.leader.entries.s.label",       action_name: "toggle_tst_sync" },
      { key: "p", label_key: "tui.leader.entries.p.label",       dispatch_method: "toggle_pause" },
      { key: "?", label_key: "tui.leader.entries.help.label",    dispatch_method: "open_help" },
      { key: ":", label_key: "tui.leader.entries.command.label", dispatch_method: "open_command" },
      { key: "q", label_key: "tui.leader.entries.q.label",       path: "/session", path_method: "delete" },
      { key: "a", label_key: "tui.leader.entries.a.label",       dispatch_method: "open_about" }
    ].freeze

    def initialize(entries: DEFAULT_ENTRIES, screen_accent: :home)
      @entries = entries
      @screen_accent = screen_accent
    end

    attr_reader :entries, :screen_accent

    def title
      I18n.t("tui.leader.title")
    end

    def resolved_entries
      entries.map do |entry|
        {
          key: entry[:key],
          label: I18n.t(entry[:label_key]),
          path: entry[:path],
          path_method: entry[:path_method],
          action_name: entry[:action_name],
          dispatch_method: entry[:dispatch_method]
        }
      end
    end
  end
end
