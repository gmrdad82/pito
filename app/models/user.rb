class User < ApplicationRecord
  has_secure_password

  # Phase 26 — 01a. Timezone foundation. UTC-storage / user-tz-render
  # is the app-wide contract; `User#time_zone` is the per-user render
  # zone, validated against the IANA tz set + Rails alias map. The
  # column defaults to `"Etc/UTC"` which doubles as the "never set"
  # sentinel — the first-load Stimulus controller detects the browser
  # zone and silently PATCHes the user's row.
  include Timezoned

  # Phase 12 — Step A. One row per active login. `dependent: :destroy`
  # so deleting a user (a future Theta concern) also clears their
  # session rows.
  has_many :sessions, dependent: :destroy

  # Phase 9 — GoogleIdentity → YoutubeConnection rename (ADR 0006).
  # A single pito account holder may connect multiple Google accounts
  # (one grant per Google account; each grant covers one or more YouTube
  # channels). Destroying the user cascades to their connections; each
  # connection's `dependent: :nullify` then preserves the user's
  # channels.
  has_many :youtube_connections, dependent: :destroy

  # Phase 25 — 01b. Trusted-location lookups + pending-session
  # introspection. Used by `Auth::NewLocationDetector` and the
  # security dashboard's pending counter.
  has_many :trusted_locations, dependent: :destroy
  has_many :login_attempts, dependent: :nullify

  # Phase 27 — 01d. Display mode switcher + three modes on `/games`.
  # The user's persisted choice of `/games` view. Default `grid` (0).
  # Integer values are load-bearing for production data and are
  # asserted in `spec/models/user_spec.rb` — do not reorder.
  enum :preferred_games_display_mode, {
    grid: 0,
    list: 1,
    shelves_by_letter: 2
  }, prefix: :games_display

  # Phase 8 — Tenant Drop + Email-Only Login.
  # Auth-only shape: email + password. No `username`, no `tenant`,
  # no `admin`. Login goes through email-only authentication
  # (see `SessionsController#create`). Email is normalized — leading
  # and trailing whitespace is stripped on assignment so user input
  # like " owner@example.test " round-trips through the form
  # without breaking the citext lookup.
  EMAIL_MAX_LENGTH = 254

  before_validation :strip_email_whitespace

  validates :password, length: { minimum: 8 }, if: -> { password.present? }
  validates :email,
            presence: true,
            length: { maximum: EMAIL_MAX_LENGTH },
            format: { with: URI::MailTo::EMAIL_REGEXP },
            uniqueness: { case_sensitive: false }

  # Phase 25 — 01b. True iff the (fingerprint, ip_prefix) pair is in
  # this user's trusted-location list. Wraps `TrustedLocation.trusted?`
  # for callers that already hold a `User`. Returns `false` on a
  # nil/blank input rather than raising — the caller's contract is "is
  # this user known here", not "validate the input".
  def trusted_location?(fingerprint:, ip_prefix:)
    TrustedLocation.trusted?(self, fingerprint, ip_prefix)
  end

  # Phase 25 — 01b. True iff this user has at least one pending-approval
  # session whose `approval_required_until` is still in the future.
  # Surfaced on `/settings/security` and via the MCP read tool.
  def has_pending_session?
    sessions.pending_within_window.exists?
  end

  private

  def strip_email_whitespace
    self.email = email.to_s.strip if email.is_a?(String)
  end
end
