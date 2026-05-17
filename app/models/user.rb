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
  # `dependent: :destroy` so a user delete cascades. 2FA is mandatory
  # (Phase 29 — Unit A2), so there is no disable path that destroys
  # backup codes outside the cascade.
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

  # Phase 27 v2 spec 05 — display-mode switcher retired. `/games`
  # collapses to a single shelves-by-letter layout; the persisted
  # `preferred_games_display_mode` enum (`grid` / `list` /
  # `shelves_by_letter`) is gone. The column was dropped in
  # `DropPreferredGamesDisplayModeFromUsers` and the
  # `Users::GamesPreferencesController` retired alongside it.

  # Phase 29 — Unit A2. User auth refactor: username login.
  # Auth-only shape: username + password. No `email`, no `tenant`,
  # no `admin`. Login goes through username authentication
  # (see `SessionsController#create`). The `username` column is
  # citext, so lookups are case-insensitive; `normalize_username`
  # strips whitespace and downcases on write so the stored form is
  # canonical. Format: alphanumerics + underscore, with single
  # internal dot or hyphen separators (no leading / trailing /
  # doubled separators), 3..32 chars.
  USERNAME_FORMAT = /\A[a-z0-9_]+(?:[.-][a-z0-9_]+)*\z/i

  before_validation :normalize_username

  validates :password, length: { minimum: 8 }, if: -> { password.present? }
  validates :username,
            presence: true,
            length: { in: 3..32 },
            format: { with: USERNAME_FORMAT },
            uniqueness: { case_sensitive: false }

  # Phase 25 — 01e. TOTP 2FA helpers. `totp_enabled?` is the single
  # canonical truth check — the seed is present AND no disable stamp
  # supersedes it. Callers in the login flow (SessionsController) and
  # the settings UI both route on this predicate; do NOT inline the
  # `totp_seed_encrypted.present?` check at call sites.
  def totp_enabled?
    totp_seed_encrypted.present? && totp_disabled_at.nil?
  end

  # Phase 29 — Unit A2. The mandatory-2FA gate's call-site predicate.
  # Identical truth to `totp_enabled?` — seed present AND no disable
  # stamp — aliased here so `Sessions::AuthConcern#require_totp_
  # configured!` and `PasswordResetsController` read clearly. The
  # `totp_enabled_at` stamp is set by the enrollment confirm; the
  # gate fires for any authenticated user who has not yet confirmed.
  def totp_configured?
    totp_enabled?
  end

  # `otpauth://totp/...` URI fed to the QR code renderer and surfaced
  # as the plaintext secret on the one-shot enrollment view. Pure
  # convenience over `ROTP::TOTP#provisioning_uri`; the issuer string
  # is centralised in `TotpHelper` so all callers agree. The account
  # label is the `username` (Phase 29 — Unit A2; was `email`).
  def totp_uri(issuer:)
    return nil if totp_seed_encrypted.blank?
    ROTP::TOTP.new(totp_seed_encrypted, issuer: issuer).provisioning_uri(username)
  end

  private

  def normalize_username
    self.username = username.to_s.strip.downcase if username.is_a?(String)
  end
end
