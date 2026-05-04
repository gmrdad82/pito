class Tenant < ApplicationRecord
  has_many :users, dependent: :destroy
  has_many :channels, dependent: :destroy

  # Phase 4 — Project Workspace associations. `dependent: :destroy` cascades
  # are deliberate: tenant cleanup is a rare admin op, but when it happens we
  # want everything tenant-scoped to go with it.
  has_many :projects, dependent: :destroy
  has_many :collections, dependent: :destroy
  has_many :games, dependent: :destroy
  has_many :footages, dependent: :destroy
  has_many :notes, dependent: :destroy
  has_many :timelines, dependent: :destroy

  validates :name, presence: true, length: { in: 3..30 }
end
