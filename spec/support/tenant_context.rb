# Phase 5A — `BelongsToTenant` raises whenever a query reaches a
# tenanted model with no `Current.tenant_id` set. Every spec type
# (request, system, model, job, mcp_tool, decorator, lib, service,
# component, feature) needs `Current.tenant` populated before any
# tenanted-model factory create / query runs.
#
# The `before(:each)` hook here pins `Current.tenant` to a default
# tenant. Factories for tenanted models use the
# `tenant { Current.tenant || association(:tenant) }` shape so they
# reuse this default rather than spinning up extras, which keeps
# default-scoped queries returning the rows the spec just created.
#
# Specs that need to assert behavior with no tenant context (the
# cross-tenant leak spec for the §5.5 step 6 "raises without Current"
# assertion) call `Current.reset` inside the example after this hook
# has fired.
#
# Specs that need to switch tenants mid-example (cross-tenant leak
# spec for steps 1–5) assign `Current.tenant = some_tenant` directly
# after creating their second tenant.

RSpec.configure do |config|
  config.before(:each) do
    Current.tenant ||= Tenant.first || FactoryBot.create(:tenant)
  end
end
