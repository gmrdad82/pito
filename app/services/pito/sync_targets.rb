module Pito
  # Pito::SyncTargets — registry of the single valid sync target.
  #
  # 2026-05-25 (collapse-to-master) — collapsed from the full per-panel /
  # per-sub-panel cascade model to a single target: "app". There is only one
  # sync indicator in the UI (the master `[ ] sync` in TST) so the target
  # universe is now exactly {"app"}.
  #
  # The `valid?` and `suppression_chain` helpers remain so call-sites in the
  # cable broadcaster suppression layer continue to compile. Both now return
  # a trivially correct result for "app" and nil/false for anything else.
  #
  # @contract see docs/architecture.md § Cable channel grammar
  module SyncTargets
    extend self

    # The full universe of known sync targets. Only the master exists.
    ALL_TARGETS = %w[app].freeze

    # Returns true when target is "app" (the only valid target).
    def valid?(target)
      target.to_s == "app"
    end

    # Returns the suppression chain for a target. For "app" this is ["app"];
    # for any other string returns nil (unknown target).
    def suppression_chain(target)
      return nil unless valid?(target)
      [ "app" ]
    end

    # Cascade targets — for "app" returns ["app"]. Kept for call-site compat.
    def cascade_targets(target)
      return [ "app" ] if target.to_s == "app"
      []
    end
  end
end
