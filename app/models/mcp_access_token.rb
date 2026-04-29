class McpAccessToken < ApplicationRecord
  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validates :last_token_preview, presence: true

  scope :active, -> { where(revoked_at: nil) }
  scope :revoked, -> { where.not(revoked_at: nil) }

  # Generates a new token, sets the digest and preview.
  # Returns the plaintext token (shown once, never stored).
  def self.generate!(name:)
    plaintext = SecureRandom.urlsafe_base64(32)
    token = create!(
      name: name,
      token_digest: digest(plaintext),
      last_token_preview: plaintext.last(4)
    )
    [ token, plaintext ]
  end

  # Finds an active token by plaintext. Returns nil if not found or revoked.
  def self.authenticate(plaintext)
    return nil if plaintext.blank?

    candidate_digest = digest(plaintext)
    token = active.find_by(token_digest: candidate_digest)
    return nil unless token
    return nil unless ActiveSupport::SecurityUtils.secure_compare(token.token_digest, candidate_digest)

    token.touch(:last_used_at)
    token
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def self.digest(plaintext)
    pepper = Rails.application.secret_key_base
    OpenSSL::HMAC.hexdigest("SHA256", pepper, plaintext)
  end
end
