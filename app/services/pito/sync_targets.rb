module Pito
  # Pito::SyncTargets — registry of every known sync target + the
  # top-down cascade map.
  #
  # 2026-05-25 (sync-rebuild) — replaces the killed localStorage-driven
  # client cascade. Server-side AppSetting rows are the single source of
  # truth for sync state; this module enumerates the universe of valid
  # targets and computes the "toggling target X writes to which rows?"
  # cascade.
  #
  # Three target tiers, all dot-namespaced:
  #
  #   "app"                          — master (one global switch)
  #   "<screen>.<panel>"             — per-panel
  #   "<screen>.<panel>.<sub_panel>" — per-sub-panel
  #
  # PANELS_BY_SCREEN must mirror what's actually rendered on each screen
  # (see `app/views/dashboard/index.html.erb` for home). PARENTS_TO_CHILDREN
  # captures every panel that decomposes into sub-panels.
  #
  # Cascade semantics (TOP-DOWN ONE-WAY):
  #
  #   * `cascade_targets("app")`                → ["app", every panel, every sub-panel]
  #   * `cascade_targets("home.stack")`         → ["home.stack", "home.stack.meilisearch", "home.stack.voyage", "home.stack.postgres", "home.stack.assets"]
  #   * `cascade_targets("home.stack.voyage")`  → ["home.stack.voyage"]
  #
  # No child→parent rollup. Toggling a child never writes the parent.
  # The cable broadcaster suppression layer reads the chain (target →
  # parent panel → "app") to decide whether to drop a payload.
  #
  # @contract see docs/architecture.md § Cable channel grammar
  module SyncTargets
    extend self

    # Every panel rendered on every screen. Sub-panels are NOT listed
    # here — they live under PARENTS_TO_CHILDREN below. Must match the
    # `target:` kwarg passed to each `Tui::SyncIndicatorComponent` on
    # the screen's view template.
    PANELS_BY_SCREEN = {
      "home" => %w[
        channels
        latest_videos
        upcoming_games
        notifications_feed
        calendar
        stack
        notifications
        security
      ]
    }.freeze

    # Every parent panel that owns sub-panel sync targets. The child
    # array is the FULL list of sub-panels that participate in the
    # cascade — a toggle on the parent uniformly writes each child.
    PARENTS_TO_CHILDREN = {
      "home.stack" => %w[
        home.stack.meilisearch
        home.stack.voyage
        home.stack.postgres
        home.stack.assets
      ]
    }.freeze

    # Flat list of every panel target (no "app", no sub-panels).
    def panel_targets
      PANELS_BY_SCREEN.flat_map { |screen, names| names.map { |n| "#{screen}.#{n}" } }
    end

    # Flat list of every sub-panel target (no "app", no panels).
    def sub_panel_targets
      PARENTS_TO_CHILDREN.values.flatten
    end

    # Every known sync target except "app" — i.e. every per-panel and
    # per-sub-panel target. Used by `cascade_targets("app")` to fan out
    # the master switch.
    def all
      panel_targets + sub_panel_targets
    end

    # Returns the cascade list for a given target: itself + every
    # descendant (top-down only).
    #
    #   cascade_targets("app")                → ["app", *all]
    #   cascade_targets("home.stack")         → ["home.stack", *its children]
    #   cascade_targets("home.stack.voyage")  → ["home.stack.voyage"]
    #   cascade_targets("home.security")      → ["home.security"]
    def cascade_targets(target)
      target = target.to_s
      return [ "app" ] + all if target == "app"
      return [ target ] + PARENTS_TO_CHILDREN[target] if PARENTS_TO_CHILDREN.key?(target)
      [ target ]
    end

    # Returns true when target is in the known universe (app, any panel,
    # any sub-panel). Used by the controller to allowlist incoming POST
    # params before writing AppSetting rows.
    def valid?(target)
      target = target.to_s
      return true if target == "app"
      return true if panel_targets.include?(target)
      return true if sub_panel_targets.include?(target)
      false
    end

    # The chain of targets that, when ANY is disabled, suppresses
    # broadcasts for `target`. Walks self → parent panel → "app" (so a
    # sub-panel inherits from its panel + master; a panel inherits from
    # master). Returns `nil` when the target is unknown.
    def suppression_chain(target)
      target = target.to_s
      return nil unless valid?(target)
      chain = [ target ]
      parent = PARENTS_TO_CHILDREN.keys.find { |p| PARENTS_TO_CHILDREN[p].include?(target) }
      chain << parent if parent
      chain << "app" unless target == "app"
      chain
    end
  end
end
