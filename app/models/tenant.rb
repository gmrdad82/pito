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

  # Phase 5A §5.3 — `slug` is the citext unique URL-safe identifier
  # for the tenant. Single-tenant world today (`primary`); the format
  # is enforced now so the schema is settled before multi-tenancy
  # work in Theta.
  SLUG_REGEX = /\A[a-z0-9][a-z0-9_-]*\z/

  validates :slug,
            presence: true,
            length: { maximum: 60 },
            format: { with: SLUG_REGEX,
                      message: "may only contain lowercase letters, digits, hyphens, and underscores" },
            uniqueness: { case_sensitive: false }
end
