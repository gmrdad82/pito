# Phase 26 — 01b/01c. Install-level per-provider webhook configuration.
# Persists the webhook URL + routing flags for each notification
# delivery provider. One row per provider; the unique index on `kind`
# enforces install-level singleton-per-provider invariant (ADR-0003 —
# the whole install is one user-base; webhook config is shared).
#
# The PORO dispatchers under `app/services/notification_delivery_channel/`
# (`Slack`, `Discord`, `InApp`) read from this table first to resolve the
# active webhook URL, falling back to `Rails.application.credentials` so
# pre-existing installs that wired the URL through credentials continue
# to deliver until the operator migrates the value into the row.
#
# `kind` carries one of the values listed in `KINDS`. New providers add
# a constant entry here AND a `NotificationDeliveryChannel::<Kind>`
# PORO under `app/services/`.
#
# `webhook_url` is probabilistically encrypted via Active Record
# Encryption — it is never compared, never queried, and an attacker who
# reads the row off disk should not be able to extract a callable
# delivery target.
#
# `everything` and `daily_digest` are independent Boolean flags
# capturing routing intent per provider. Both default to `false`; both
# are mutable from the Settings pane.
#
# `last_validated_at` records the time the most recent test ping
# succeeded. The pane refuses to persist the row until a 2xx ping has
# landed for the URL.
#
# 2026-05-16 webhook-clear UX tweak.
# `webhook_url` is now nullable at the DB level. A nil URL represents
# "integration cleared" — the row stays on the table (so the panes can
# render a stable empty form) but no delivery target is configured.
# The `nilify_blank_webhook_url_and_zero_flags` callback enforces the
# invariant "URL nil implies both flags false" at the model layer so
# every surface (web form, MCP tool, console, future CLI) lands on the
# same state shape without each controller having to special-case it.
class NotificationDeliveryChannel < ApplicationRecord
  # Active Record Encryption — probabilistic (not deterministic). The
  # URL is never the target of a `where(webhook_url: ...)` lookup; we
  # always lookup by `kind`. Probabilistic encryption rotates the IV
  # per-write and offers stronger ciphertext guarantees.
  encrypts :webhook_url

  KINDS = %w[slack discord].freeze

  # Provider-specific URL shape. The pane reuses these constants so the
  # client-side error message matches the server-side validation exactly.
  SLACK_URL_REGEX = %r{\Ahttps://hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]+\z}
  DISCORD_URL_REGEX = %r{\Ahttps://(?:discord\.com|discordapp\.com)/api/webhooks/\d+/[A-Za-z0-9_\-]+\z}

  # 2026-05-16 webhook-clear UX tweak.
  # Normalize a blank `webhook_url` to nil and zero both routing flags
  # in the same save. Runs before validation so the URL-format
  # validator can short-circuit on `webhook_url.nil?` cleanly. Without
  # this callback a controller setting `webhook_url: ""` + `everything: true`
  # could land in the "URL absent, flags on" silent-no-op state.
  before_validation :nilify_blank_webhook_url_and_zero_flags

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :kind, uniqueness: { case_sensitive: false }
  validate :webhook_url_must_match_kind
  validate :flags_require_webhook_url

  scope :for_kind, ->(kind) { where(kind: kind.to_s) }

  # Phase 16 dispatcher entry point — returns a PORO instance ready to
  # `deliver(notification)`. The AR model exposes the dispatcher so
  # existing call sites (`NotificationDeliveryChannel.for("discord")`)
  # keep working after the Phase 26 PORO rebase.
  def self.for(kind)
    Base.for(kind)
  end

  # Install-level singleton lookup for the AR row. Returns the one row
  # (or nil) for the given `kind`. Callers needing a NEW unsaved row
  # should use `for_kind(kind).first_or_initialize(kind: kind)`.
  def self.find_record_for(kind)
    for_kind(kind).first
  end

  # Convenience shorthands the PORO dispatchers use to resolve the
  # active webhook URL for their kind from the AR row.
  def self.slack
    find_record_for("slack")
  end

  def self.discord
    find_record_for("discord")
  end

  # Returns true iff `webhook_url` matches the per-kind regex. Surfaced
  # to controllers + pane validators so the same regex check is enforced
  # at the boundary (controller) and the model (last line of defense).
  def valid_url?
    return false if webhook_url.blank?

    regex_for_kind&.match?(webhook_url) || false
  end

  private

  def regex_for_kind
    case kind.to_s
    when "slack"   then SLACK_URL_REGEX
    when "discord" then DISCORD_URL_REGEX
    end
  end

  def webhook_url_must_match_kind
    return if kind.blank? || webhook_url.blank?
    return if valid_url?

    errors.add(:webhook_url, "is not a valid #{kind} webhook URL.")
  end

  # 2026-05-16 webhook-clear UX tweak.
  # The callback below zeroes both flags whenever the URL is blank so
  # this validator is normally a no-op. It still fires as defense in
  # depth: if a future code path bypasses the callback (e.g. via
  # `update_columns`-style writes that skip callbacks AND skip
  # validations together) and somehow lands a flag=true + URL=nil row,
  # the validator surfaces the contradiction. The same posture also
  # rejects a wire payload that explicitly sets `everything: "yes"`
  # alongside a blank URL field — the form-tampered case the spec
  # call-out names.
  def flags_require_webhook_url
    return if webhook_url.present?
    return unless everything? || daily_digest?

    errors.add(:base, "routing flags require a webhook URL.")
  end

  # 2026-05-16 webhook-clear UX tweak.
  # Strip + nilify a blank `webhook_url`, then zero both routing flags
  # in the same save when the URL ends up nil. Operates idempotently:
  # a save with a present URL and flags is untouched.
  def nilify_blank_webhook_url_and_zero_flags
    self.webhook_url = webhook_url.to_s.strip
    self.webhook_url = nil if webhook_url.blank?
    return if webhook_url.present?

    self.everything = false
    self.daily_digest = false
  end
end
