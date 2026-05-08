class User < ApplicationRecord
  has_secure_password

  belongs_to :tenant

  # Phase 12 — Step A. One row per active login. `dependent: :destroy`
  # so deleting a user (a future Theta concern) also clears their
  # session rows.
  has_many :sessions, dependent: :destroy

  # Phase 12 — Step A. The implicit pin (`User.first`) is replaced by a
  # cookie-resolved current user. Authenticate via `User#authenticate`
  # (provided by `has_secure_password`); minimum password length keeps
  # Beta from accepting trivially short seeds without forcing a reset
  # flow we have not built yet. The `password` accessor is transient
  # (only present when a fresh password is being set), so the validation
  # naturally only runs on create or password-change paths.
  validates :password, length: { minimum: 8 }, if: -> { password.present? }

  USERNAME_REGEX = /\A[A-Za-z][A-Za-z0-9]*\z/

  validates :username,
            presence: true,
            format: { with: USERNAME_REGEX },
            uniqueness: { case_sensitive: false }
  validates :email,
            presence: true,
            format: { with: URI::MailTo::EMAIL_REGEXP },
            uniqueness: { case_sensitive: false }

  # Class method: find a user by username OR email. Strips whitespace; the
  # citext columns make the comparison case-insensitive automatically.
  def self.find_by_username_or_email(login)
    return nil if login.blank?

    login = login.to_s.strip
    return nil if login.empty?

    where("username = ? OR email = ?", login, login).first
  end
end
