class Production < ApplicationRecord
  belongs_to :video, optional: true

  enum :status, { idea: 0, in_progress: 1, published: 2, archived: 3 }

  validates :title, presence: true
end
