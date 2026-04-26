class SavedView < ApplicationRecord
  enum :kind, { channels: 0, videos: 1 }

  validates :kind, presence: true
  validates :url, presence: true, uniqueness: { scope: :kind }
  validates :name, presence: true

  def display_name
    "#{kind.titleize}: #{name}"
  end
end
