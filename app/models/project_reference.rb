# Phase 4 §4 — polymorphic join between Project and (Game | Collection).
# Strict allowlist on `referenceable_type`; cross-tenant references are
# rejected (the referenced record must share `tenant_id` with the project).
class ProjectReference < ApplicationRecord
  ALLOWED_TYPES = %w[Game Collection].freeze

  include BelongsToTenant

  belongs_to :project
  belongs_to :referenceable, polymorphic: true

  validates :referenceable_type, inclusion: { in: ALLOWED_TYPES }
  validates :project_id,
            uniqueness: { scope: [ :referenceable_type, :referenceable_id ] }
  validate :referenceable_must_share_tenant
  validate :tenant_must_match_project

  before_validation :denormalize_tenant_from_project

  private

  # Phase 5A — backfill `tenant_id` from the parent project when no
  # explicit value was assigned by the caller.
  #
  # The `BelongsToTenant` default scope stamps `tenant_id` from
  # `Current.tenant_id` on freshly built rows (Rails copies scope
  # `where` conditions onto new-record attribute defaults). That
  # stamp is indistinguishable on its own from an explicit assign,
  # so we treat `tenant_id == Current.tenant_id` as "default stamp"
  # and let `project.tenant_id` win in that case. An explicit
  # tenant_id that disagrees with both Current AND the project flows
  # through unchanged so the `tenant_must_match_project` validator
  # can reject it.
  def denormalize_tenant_from_project
    return unless project

    if tenant_id.nil? || tenant_id == Current.tenant_id
      self.tenant_id = project.tenant_id
    end
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
