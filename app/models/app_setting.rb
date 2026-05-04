class AppSetting < ApplicationRecord
  encrypts :value, deterministic: true

  validates :key, presence: true, uniqueness: { case_sensitive: false }
  validates :value, presence: true

  def self.get(key)
    find_by(key: key)&.value
  end

  def self.set(key, value)
    record = find_or_initialize_by(key: key)
    record.update!(value: value)
    record
  end

  # Phase 4 §3.5 (2026-05-04 post-review refinement) — Voyage call gating.
  # The boolean lives on the first AppSetting row (the de-facto singleton seeded
  # in db/seeds.rb). Defaults to `false` so dev/test never hit Voyage on dummy
  # data; production seeds flip it `true`. Phase B's Settings UI flips it at
  # runtime — no Rails restart required (this is the whole point of pivoting
  # away from `Rails.application.config`).
  def self.voyage_embeddings_enabled?
    first&.voyage_embeddings_enabled || false
  end
end
