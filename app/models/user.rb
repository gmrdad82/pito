class User < ApplicationRecord
  has_secure_password

  # Phase 25 — 01e. TOTP 2FA seed. Stored encrypted at rest via Active
  # Record Encryption (LD-9). The plaintext base32 seed is what `rotp`
  # consumes to verify 6-digit codes; the column is `:text` because the
  # encrypted envelope is larger than the 32-char plaintext seed.
  #
  # `totp_enabled_at` is stamped when the user successfully confirms a
  # freshly generated seed with a valid 6-digit code from their
  # authenticator app. `totp_disabled_at` is stamped on the disable
  # path so the audit trail can answer "was TOTP ever on" without
  # scraping `AuthAuditLog`. `totp_enabled?` is the canonical truth
  # check — seed present AND no disabled stamp.
  encrypts :totp_seed_encrypted

  # Phase 25 — 01e. Backup codes. Ten single-use codes minted on
  # enable; each row carries a BCrypt digest (never the plaintext).
  # `dependent: :destroy` so a user delete cascades; `Auth::TotpDisabler`
  # destroys rows directly when 2FA is turned off.
  has_many :totp_backup_codes, dependent: :destroy

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
  # Rails 8.1 — defensive: lock the enum-backing column type.
  attribute :preferred_games_display_mode, :integer
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

  # Phase 25 — 01e. TOTP 2FA helpers. `totp_enabled?` is the single
  # canonical truth check — the seed is present AND no disable stamp
  # supersedes it. Callers in the login flow (SessionsController) and
  # the settings UI both route on this predicate; do NOT inline the
  # `totp_seed_encrypted.present?` check at call sites.
  def totp_enabled?
    totp_seed_encrypted.present? && totp_disabled_at.nil?
  end

  # `otpauth://totp/...` URI fed to the QR code renderer and surfaced
  # as the plaintext secret on the one-shot enrollment view. Pure
  # convenience over `ROTP::TOTP#provisioning_uri`; the issuer string
  # is centralised in `TotpHelper` so all callers agree.
  def totp_uri(issuer:)
    return nil if totp_seed_encrypted.blank?
    ROTP::TOTP.new(totp_seed_encrypted, issuer: issuer).provisioning_uri(email)
  end

  private

  def strip_email_whitespace
    self.email = email.to_s.strip if email.is_a?(String)
  end
end
