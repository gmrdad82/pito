class User < ApplicationRecord
  has_secure_password

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

  private

  def strip_email_whitespace
    self.email = email.to_s.strip if email.is_a?(String)
  end
end
