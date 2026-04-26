class Note < ApplicationRecord
  enum :kind, { idea: 0, log: 1, todo: 2, reference: 3 }

  validates :title, presence: true
end
