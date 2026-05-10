# Phase 4 §4 — polymorphic join between Project and (Game | Collection).
# Strict allowlist on `referenceable_type`.
#
# Phase 8 — tenant drop. The `tenant_id` column and the cross-tenant
# guards (`referenceable_must_share_tenant`, `tenant_must_match_project`)
# are gone. Install-wide visibility means a Project can reference any
# Game or Collection in the install.
class ProjectReference < ApplicationRecord
  ALLOWED_TYPES = %w[Game Collection].freeze

  belongs_to :project
  belongs_to :referenceable, polymorphic: true

  validates :referenceable_type, inclusion: { in: ALLOWED_TYPES }
  validates :project_id,
            uniqueness: { scope: [ :referenceable_type, :referenceable_id ] }
end
