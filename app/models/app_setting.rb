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

  # Phase 29 (settings refactor) — the Voyage.ai pane and the per-target
  # `voyage_index_project_notes` flag column are both dropped. Indexing is
  # gated solely on credentials presence now: a configured Voyage API key
  # means embeddings are eligible for any indexer that calls this gate.
  # `Notes::EmbedJob` short-circuits when this is false.
  def self.voyage_configured?
    Rails.application.credentials.dig(:voyage, :api_key).to_s.strip.present?
  end

  # Phase 29 (settings refactor) — predicate now equals
  # `voyage_configured?`. The per-target flag column is gone; with no
  # operator-facing toggle, "key configured" is the only signal.
  # Callers (`Notes::EmbedJob`) can keep the two-call shape
  # (`voyage_indexing_project_notes? && voyage_configured?`) for
  # readability; both predicates resolve to the same boolean today.
  def self.voyage_indexing_project_notes?
    voyage_configured?
  end

  # Phase 29 — Unit A1 (Part 4 delivery bug fix). "Is Discord delivery
  # on" is derived entirely from the `NotificationDeliveryChannel` row
  # for the kind — its existence plus a present `webhook_url` and at
  # least one routing flag set (`everything` or `daily_digest`). The
  # orphaned `AppSetting.discord_enabled` boolean was never written by
  # the webhook controllers, so the old gate was always false and
  # Discord delivery was silently dead. The column is dropped; this
  # predicate is the new source of truth.
  def self.discord_delivery_enabled?
    delivery_channel_enabled?("discord")
  end

  # Phase 29 — Unit A1 (Part 4 delivery bug fix). Slack mirror of
  # `discord_delivery_enabled?` — derived from the
  # `NotificationDeliveryChannel` row for the kind, never the dropped
  # `slack_enabled` column.
  def self.slack_delivery_enabled?
    delivery_channel_enabled?("slack")
  end

  # True iff a `NotificationDeliveryChannel` row exists for the kind
  # with a present `webhook_url` and at least one routing flag
  # (`everything` or `daily_digest`) set. This is the single source of
  # truth for the "delivery is on" gate the dispatchers read.
  def self.delivery_channel_enabled?(kind)
    row = NotificationDeliveryChannel.find_record_for(kind)
    return false if row.nil?
    return false if row.webhook_url.to_s.strip.empty?

    row.everything? || row.daily_digest?
  end
  private_class_method :delivery_channel_enabled?

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
end
