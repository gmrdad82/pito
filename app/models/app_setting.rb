class AppSetting < ApplicationRecord
  encrypts :value, deterministic: true

  validates :key, presence: true, uniqueness: { case_sensitive: false }
  validates :value, presence: true

  def self.get(key)
    find_by(key: key)&.value
  end

  def self.set(key, value)
    record = find_or_initialize_by(key: key)
    record.update!(value: value)
    record
  end

  # 2026-05-25 (sync-rebuild) — server-side sync state, replaces the
  # killed `pito.sync.*` localStorage layer.
  #
  # One AppSetting row per target. Targets are dot-namespaced strings:
  #
  #   sync.app                          — master (single global switch)
  #   sync.<screen>.<panel>             — per-panel
  #   sync.<screen>.<panel>.<sub_panel> — per-sub-panel
  #
  # Value semantics ride the yes/no boundary contract:
  #   "yes" → enabled (default when the row is absent)
  #   "no"  → user-disabled
  #
  # The full target catalog + cascade rules live in `Pito::SyncTargets`.
  # The toggle controller + the cable broadcaster suppression layer both
  # call into these two helpers; nothing else reads the rows directly.
  SYNC_KEY_PREFIX = "sync.".freeze

  def self.sync_enabled?(target)
    get("#{SYNC_KEY_PREFIX}#{target}") != "no"
  end

  def self.set_sync(target, enabled)
    set("#{SYNC_KEY_PREFIX}#{target}", enabled ? "yes" : "no")
  end

  # Phase 29 (settings refactor) — the Voyage.ai pane and the per-target
  # `voyage_index_project_notes` flag column are both dropped. Indexing
  # is gated solely on credentials presence now: a configured Voyage API
  # key means embeddings are eligible for any indexer that calls this
  # gate. The Notes feature (and its `Notes::EmbedJob`) was dropped
  # 2026-05-21 (D17); the gate remains for game/bundle/channel indexers.
  def self.voyage_configured?
    Rails.application.credentials.dig(:voyage, :api_key).to_s.strip.present?
  end

  # 2026-05-20 — F3-B-SIMPLIFY-MODEL. "Is Discord delivery on" is now
  # derived from two independent signals AND'd together:
  #
  #   1. The install-level shared toggle (`notifications_send_all` or
  #      `notifications_send_daily_digest`) — at least one is ON.
  #   2. A `NotificationDeliveryChannel` row for the kind exists with a
  #      present `webhook_url`.
  #
  # The shared toggle is the operator-controlled master switch (it can
  # be flipped ON without any webhook configured — the per-brand
  # webhook gate decides which providers actually receive deliveries).
  def self.discord_delivery_enabled?
    delivery_channel_enabled?("discord")
  end

  # 2026-05-20 — F3-B-SIMPLIFY-MODEL. Slack mirror of
  # `discord_delivery_enabled?` — same two-signal AND.
  def self.slack_delivery_enabled?
    delivery_channel_enabled?("slack")
  end

  # True iff:
  #   - At least one shared notification toggle is ON
  #     (`notifications_send_all || notifications_send_daily_digest`).
  #   - A `NotificationDeliveryChannel` row exists for the kind with a
  #     present `webhook_url`.
  #
  # Per-brand routing flags no longer exist; the shared toggles cover
  # the install-wide intent and per-brand webhook presence covers the
  # provider-level dispatch.
  def self.delivery_channel_enabled?(kind)
    return false unless notifications_any_toggle_on?

    row = NotificationDeliveryChannel.find_record_for(kind)
    return false if row.nil?
    return false if row.webhook_url.to_s.strip.empty?

    true
  end
  private_class_method :delivery_channel_enabled?

  # 2026-05-20 — F3-B-SIMPLIFY-MODEL. Convenience predicates for the
  # two shared notification toggles. Both read from the canonical
  # `AppSetting.singleton_row` and never touch the per-brand
  # `NotificationDeliveryChannel` rows.
  def self.notifications_send_all?
    singleton_row.notifications_send_all
  end

  def self.notifications_send_daily_digest?
    singleton_row.notifications_send_daily_digest
  end

  # True iff at least one of the shared toggles is on. Acts as the
  # install-level "any notifications go out" gate.
  def self.notifications_any_toggle_on?
    notifications_send_all? || notifications_send_daily_digest?
  end

  # Flip a single shared notification toggle by name. `column` MUST be
  # one of the two canonical column symbols. Raises ArgumentError for
  # anything else so the controller's allowlist is the only place this
  # can be called from.
  NOTIFICATION_TOGGLE_COLUMNS = %i[
    notifications_send_all notifications_send_daily_digest
  ].freeze

  def self.set_notification_toggle!(column, value)
    column = column.to_sym
    unless NOTIFICATION_TOGGLE_COLUMNS.include?(column)
      raise ArgumentError, "unknown notification toggle: #{column.inspect}"
    end

    singleton_row.update!(column => !!value)
  end

  # Phase 32 follow-up (2026-05-16) — three-layer reindex lock.
  #
  # The Meilisearch reindex job is install-wide singleton work (pito is
  # single-install, multi-user per ADR 0003). The two columns added by
  # the AddReindexFlagsToAppSettings migration live on this table even
  # though it is otherwise key/value-shaped; rather than reading the
  # columns off of arbitrary rows, the predicates below promote one
  # canonical row (`key = "__singleton__"`) to be the lock anchor. The
  # row is created on first access and re-used forever.
  #
  # `reindex_running?`         — Layer 1 gate the controller reads.
  # `start_reindex!`           — flips the flag + stamps started_at in
  #                              an atomic update; returns the row.
  # `clear_reindex_lock!`      — cleanup invoked from the job's `ensure`
  #                              block AND from the rake escape hatch
  #                              (`bin/rails pito:state:clear_reindex_lock`).
  # `reindex_started_at`       — for the UI "started ~Xs ago" string;
  #                              nil when idle.
  SINGLETON_KEY = "__singleton__".freeze

  def self.singleton_row
    row = find_by(key: SINGLETON_KEY)
    return row if row

    # `value` is encrypted + non-null + uniqueness-constrained on key;
    # the placeholder string is never read but must satisfy the
    # presence validation. `find_or_create_by!` would race with the
    # uniqueness check; the explicit find-then-create is fine because
    # the row is created exactly once in the install lifetime.
    create!(key: SINGLETON_KEY, value: "singleton")
  rescue ActiveRecord::RecordNotUnique
    find_by!(key: SINGLETON_KEY)
  end

  def self.reindex_running?
    singleton_row.reindex_running
  end

  def self.reindex_started_at
    singleton_row.reindex_started_at
  end

  def self.start_reindex!
    singleton_row.update!(reindex_running: true, reindex_started_at: Time.current)
  end

  def self.clear_reindex_lock!
    singleton_row.update!(reindex_running: false, reindex_started_at: nil)
  end

  # 2026-05-25 (collapse-to-master) — master sync pause flag.
  #
  # `master_sync_paused` is a boolean column on the singleton row. When true
  # all sync activity (background jobs, cable broadcasts) is suppressed.
  # Replaces the prior `paused_targets` JSON array (which held per-panel /
  # per-sub-panel pause state — now gone).
  #
  # `master_sync_paused?` — returns true when the master pause is active.
  # `pause_master!`        — sets the flag to true, atomically.
  # `resume_master!`       — clears the flag, atomically.
  #
  # Callers use `Pito::SyncState` instead of calling these directly; the
  # service layer owns broadcasts.

  def self.master_sync_paused?
    singleton_row.master_sync_paused
  end

  def self.pause_master!
    singleton_row.update!(master_sync_paused: true)
  end

  def self.resume_master!
    singleton_row.update!(master_sync_paused: false)
  end
end
