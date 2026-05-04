# Phase 4 §4 — polymorphic join between Project and (Game | Collection).
# Strict allowlist on `referenceable_type`; cross-tenant references are
# rejected (the referenced record must share `tenant_id` with the project).
class ProjectReference < ApplicationRecord
  ALLOWED_TYPES = %w[Game Collection].freeze

  belongs_to :tenant
  belongs_to :project
  belongs_to :referenceable, polymorphic: true

  validates :referenceable_type, inclusion: { in: ALLOWED_TYPES }
  validates :project_id,
            uniqueness: { scope: [ :referenceable_type, :referenceable_id ] }
  validate :referenceable_must_share_tenant
  validate :tenant_must_match_project

  before_validation :denormalize_tenant_from_project

  private

  def denormalize_tenant_from_project
    self.tenant_id ||= project&.tenant_id
  end

  def referenceable_must_share_tenant
    return if project.blank? || referenceable.blank?
    return unless referenceable.respond_to?(:tenant_id)

    if referenceable.tenant_id != project.tenant_id
      errors.add(:referenceable, "must belong to the same tenant as the project")
    end
  end

  def tenant_must_match_project
    return if project.blank? || tenant_id.blank?

    if tenant_id != project.tenant_id
      errors.add(:tenant_id, "must match the project's tenant")
    end
  end
end
