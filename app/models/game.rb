# Phase 4 §3.3 — Game has a title, optional collection, and a strict-allowlisted
# jsonb `platforms` array. Cover-art uploads via Active Storage; variants
# `thumbnail (100x100)`, `card (300x300)`, `full (resize_to_limit 4096)`.
class Game < ApplicationRecord
  # Allowlist of platform strings accepted in the `platforms[].platform`
  # field. No "Other", no free text — keeps downstream filtering simple
  # and prevents typos from polluting the dataset.
  ALLOWED_PLATFORMS = %w[
    PS5 PS4
    Xbox\ Series Xbox\ One
    Switch
    PC Mac
    Mobile
  ].freeze

  belongs_to :tenant
  belongs_to :collection, optional: true

  has_many :footages, dependent: :nullify

  has_one_attached :cover_art

  validates :title, presence: true, length: { maximum: 255 }
  validate :platforms_must_be_array_of_allowed_triples

  attribute :title, :string, default: "Untitled game"

  # Active Storage variants. The vips processor (config/application.rb) handles
  # resize. Variants render lazily on first request to a variant URL.
  def cover_art_thumbnail
    cover_art.variant(resize_to_limit: [ 100, 100 ])
  end

  def cover_art_card
    cover_art.variant(resize_to_limit: [ 300, 300 ])
  end

  def cover_art_full
    cover_art.variant(resize_to_limit: [ 4096, 4096 ])
  end

  private

  def platforms_must_be_array_of_allowed_triples
    return errors.add(:platforms, "must be an array") unless platforms.is_a?(Array)

    platforms.each_with_index do |entry, idx|
      unless entry.is_a?(Hash)
        errors.add(:platforms, "[#{idx}] must be a hash")
        next
      end

      platform = entry["platform"] || entry[:platform]
      unless ALLOWED_PLATFORMS.include?(platform)
        errors.add(:platforms, "[#{idx}].platform must be one of #{ALLOWED_PLATFORMS.join(', ')}")
      end

      %w[owned recorded_on].each do |key|
        value = entry[key].nil? ? entry[key.to_sym] : entry[key]
        next if value.nil? # presence not required at the model layer
        unless [ true, false ].include?(value)
          errors.add(:platforms, "[#{idx}].#{key} must be a boolean")
        end
      end
    end
  end
end
