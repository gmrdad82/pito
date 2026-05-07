# Phase 5A §5.4 — uniform tenant scoping for every data-holding model.
#
# Including this concern:
#   * declares `belongs_to :tenant`
#   * validates `tenant_id` presence
#   * adds a default scope keyed on `Current.tenant_id`
#
# Locked decision (5A): when `Current.tenant_id` is nil, every query
# against a tenanted model raises `BelongsToTenant::TenantContextMissing`.
# Bugs should be loud, not silent — a missing tenant context is a
# programming error, not a state to silently tolerate.
#
# Tests that legitimately need to bypass the scope use `Model.unscoped`
# explicitly. There is no `with_tenant_context_optional` helper.
module BelongsToTenant
  extend ActiveSupport::Concern

  # Raised whenever a query reaches a tenanted model without a
  # `Current.tenant_id` set. Rescued in upstream code only at the
  # outermost boundary (e.g. controller-level rescue_from); inner code
  # should let the exception bubble.
  class TenantContextMissing < StandardError; end

  included do
    belongs_to :tenant
    validates :tenant_id, presence: true

    default_scope do
      if Current.tenant_id
        where(tenant_id: Current.tenant_id)
      else
        raise TenantContextMissing,
              "Current.tenant_id required for #{name} (default scope on a " \
              "tenanted model was reached with no tenant context). Set " \
              "`Current.tenant = ...` before querying, or use " \
              "`#{name}.unscoped` to bypass the scope explicitly."
      end
    end
  end
end
