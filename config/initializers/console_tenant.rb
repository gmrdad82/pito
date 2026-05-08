# Auto-set Current.tenant and Current.user when `bin/rails console` boots.
#
# Rails currently has no signup/login UI: Tenant and User are seeded
# singletons (see CLAUDE.md "Architecture notes"). HTTP requests pin
# Current.tenant / Current.user via a before_action in
# ApplicationController, but `rails console` skips that layer, which
# means BelongsToTenant's strict guard fires on any tenant-scoped query
# the moment you open a console.
#
# The block below runs once on console boot only — not on HTTP requests,
# not in tests, not in Sidekiq workers. It mirrors what a logged-in
# request would do, so console sessions can query Channel, Video, etc.
# without manually seeding Current.* every time.
Rails.application.console do
  Current.tenant = Tenant.first
  Current.user = User.first
  puts "[pito] Current.tenant=#{Current.tenant&.id.inspect} Current.user=#{Current.user&.id.inspect}"
end
