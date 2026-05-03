class User < ApplicationRecord
  has_secure_password

  belongs_to :tenant

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
