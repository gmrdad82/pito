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
end
