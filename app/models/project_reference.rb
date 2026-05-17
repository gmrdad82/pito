# Phase 4 §4 / Phase 27 follow-up (2026-05-17) — polymorphic join
# between Project and Game.
#
# Strict allowlist on `referenceable_type`. The Collection model was
# removed in the 2026-05-17 simplification (every grouping is now a
# Bundle); only `Game` survives as a referenceable target. Historical
# `referenceable_type = "Collection"` rows would fail validation on
# next save; the DB column itself still permits any string (no DB-level
# enum), so old rows are tolerated until manually cleaned.
#
# Phase 8 — tenant drop. The `tenant_id` column and the cross-tenant
# guards are gone. Install-wide visibility means a Project can
# reference any Game in the install.
class ProjectReference < ApplicationRecord
  ALLOWED_TYPES = %w[Game].freeze

  belongs_to :project
  belongs_to :referenceable, polymorphic: true

  validates :referenceable_type, inclusion: { in: ALLOWED_TYPES }
  validates :project_id,
            uniqueness: { scope: [ :referenceable_type, :referenceable_id ] }
end
