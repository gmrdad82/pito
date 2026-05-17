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
# The `nilify_blank_webhook_url` (before_validation) +
# `zero_flags_when_webhook_url_blank` (before_save) callback pair
# enforces the invariant "URL nil implies both flags false" at the
# model layer so every surface (web form, MCP tool, console, future
# CLI) lands on the same state shape without each controller having
# to special-case it.
#
# 2026-05-17 — the original combined `nilify_blank_webhook_url_and_zero_flags`
# `before_validation` callback was split: the flag-zeroing half moved to
# `before_save` so the `flags_require_webhook_url` validator sees the
# user-submitted intent (flag-on with blank URL) and fails loudly,
# instead of silently no-opping after the callback already coerced the
# flag to false.
class NotificationDeliveryChannel < ApplicationRecord
  # Active Record Encryption — probabilistic (not deterministic). The
  # URL is never the target of a `where(webhook_url: ...)` lookup; we
  # always lookup by `kind`. Probabilistic encryption rotates the IV
  # per-write and offers stronger ciphertext guarantees.
  encrypts :webhook_url

  KINDS = %w[slack discord].freeze

  # User-facing brand labels for the `kind` enum. The raw `kind` value
  # is lowercase ("slack" / "discord") for URL routing + DB storage; the
  # brand-as-proper-noun spelling ("Slack" / "Discord") is what every
  # user-facing surface (validation error copy, flash messages) MUST
  # use. Centralized here so every interpolation in this model reads
  # the same canonical map.
  BRAND_LABELS = {
    "slack"   => "Slack",
    "discord" => "Discord"
  }.freeze

  # Provider-specific URL shape. The pane reuses these constants so the
  # client-side error message matches the server-side validation exactly.
  SLACK_URL_REGEX = %r{\Ahttps://hooks\.slack\.com/services/T[A-Z0-9]+/B[A-Z0-9]+/[A-Za-z0-9]+\z}
  DISCORD_URL_REGEX = %r{\Ahttps://(?:discord\.com|discordapp\.com)/api/webhooks/\d+/[A-Za-z0-9_\-]+\z}

  # 2026-05-17 host-allowlist hardening.
  #
  # The per-kind regexes above already pin the host as part of the full
  # URL shape, but the host check is path-coupled — if a future tweak
  # loosens the path component, the host pinning could regress silently.
  # The explicit host allowlist below is a defense-in-depth layer that
  # validates the parsed URI host against the canonical brand domains
  # independently of the path regex. Exact host match only (no suffix /
  # subdomain matching) so `evilhooks.slack.com.attacker.com` cannot
  # slip through, and HTTPS is required (`URI::HTTPS` instance check).
  #
  # Discord ships webhooks under both `discord.com` (canonical) and
  # `discordapp.com` (legacy) — both are accepted. Slack only ships
  # under `hooks.slack.com`.
  ALLOWED_WEBHOOK_HOSTS = {
    "slack"   => %w[hooks.slack.com].freeze,
    "discord" => %w[discord.com discordapp.com].freeze
  }.freeze

  # 2026-05-16 webhook-clear UX tweak.
  # Normalize a blank `webhook_url` to nil before validation so the
  # URL-format validator (and the host-allowlist validator) can
  # short-circuit on `webhook_url.nil?` cleanly.
  #
  # 2026-05-17 — the flag-zeroing half of the original callback moved
  # to `before_save` (post-validation). Zeroing flags BEFORE validation
  # silently swallowed the "flag on, URL blank" intent — the
  # `flags_require_webhook_url` validator returned early because the
  # flag was already false by the time it ran, so `save` returned true
  # and the controller flashed "on" even though the DB stored false.
  # Keeping nilification pre-validation (so URL-format checks bail
  # cleanly) and deferring flag-zeroing to post-validation lets the
  # validator see the user's actual intent and fail loudly.
  before_validation :nilify_blank_webhook_url
  before_save :zero_flags_when_webhook_url_blank

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :kind, uniqueness: { case_sensitive: false }
  validate :webhook_url_host_must_match_kind
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

    errors.add(:webhook_url, "is not a valid #{brand_label} webhook URL.")
  end

  # 2026-05-17 host-allowlist hardening.
  #
  # Defense-in-depth host check. The per-kind regex above already pins
  # the host as part of the full URL shape; this validator parses the
  # URL and asserts the host against the explicit per-kind allowlist
  # independently — so a future change to the path component cannot
  # regress the host pinning. Also enforces HTTPS via the `URI::HTTPS`
  # instance check (an `http://hooks.slack.com/...` URL would be a
  # `URI::HTTP` instance and fail here even if the host matched).
  def webhook_url_host_must_match_kind
    return if kind.blank? || webhook_url.blank?

    allowed = ALLOWED_WEBHOOK_HOSTS[kind.to_s]
    return if allowed.blank?

    uri = URI.parse(webhook_url)
    return if uri.is_a?(URI::HTTPS) && allowed.include?(uri.host)

    errors.add(
      :webhook_url,
      "must be a #{brand_label} webhook URL (https://#{allowed.first}/...)."
    )
  rescue URI::InvalidURIError
    errors.add(:webhook_url, "is not a valid URL.")
  end

  # 2026-05-17 — the primary user-facing role of this validator is to
  # block the auto-save toggle's "flag on, URL blank" attempt and
  # surface a flash alert ("Slack webhook URL not configured.") so the
  # toggle visibly reverts on the next render.
  #
  # Kind-specific copy lets the same message stay accurate whether the
  # offending toggle is on the Slack pane or the Discord pane. The
  # `:base` error keeps `errors.full_messages.to_sentence` clean (no
  # `Base routing flags ...` prefix).
  #
  # Only fires on a transition INTO `true` for a flag — i.e. when
  # `everything_changed?(to: true)` or `daily_digest_changed?(to: true)`.
  # This is deliberate: a legacy row with a stale `true` flag and a
  # blank URL must remain togglable OFF without first satisfying the
  # validator. Without the `_changed?(to: true)` guard, a user trying
  # to flip `everything` OFF on such a row would be blocked because
  # the other flag is still `true` in memory.
  #
  # The `zero_flags_when_webhook_url_blank` `before_save` callback acts
  # as a defense-in-depth post-validation guard for code paths that
  # somehow bypass validation (e.g. `update_columns` skipping both
  # callbacks and validations together): once validation has run, any
  # surviving flag-on-with-blank-URL state gets quietly normalized so
  # the persisted row never violates the invariant.
  def flags_require_webhook_url
    return if webhook_url.present?

    turning_on =
      everything_changed?(to: true) ||
      daily_digest_changed?(to: true)
    return unless turning_on

    errors.add(:base, "#{brand_label} webhook URL not configured.")
  end

  # Resolve the lowercase `kind` to the proper-noun brand label. Falls
  # back to a capitalized form if `kind` is somehow blank or unknown,
  # so the error message stays grammatical instead of dropping into an
  # empty string mid-sentence.
  def brand_label
    BRAND_LABELS[kind.to_s] || kind.to_s.capitalize.presence || "This"
  end

  # 2026-05-16 webhook-clear UX tweak / 2026-05-17 split.
  # Strip + nilify a blank `webhook_url`. Runs pre-validation so the
  # URL-format + host-allowlist validators can cleanly short-circuit
  # on `webhook_url.nil?`.
  def nilify_blank_webhook_url
    self.webhook_url = webhook_url.to_s.strip
    self.webhook_url = nil if webhook_url.blank?
  end

  # 2026-05-17 — post-validation flag normalization.
  # If validation passed AND the URL ended up blank, zero both routing
  # flags so the persisted row is internally consistent. In the normal
  # "flag on, URL blank" case the `flags_require_webhook_url`
  # validator already blocked the save, so this callback never runs for
  # that scenario — it only fires when the URL is being cleared
  # legitimately (e.g. the webhook controller's `clear` keyword, which
  # explicitly assigns `everything: false, daily_digest: false`
  # alongside `webhook_url: nil`).
  def zero_flags_when_webhook_url_blank
    return if webhook_url.present?

    self.everything = false
    self.daily_digest = false
  end
end
