# Phase 20 — friendly URLs.
#
# Helper for controllers that render a slugged resource. After looking up
# the record via `Model.friendly.find(params[:id])`, call
# `redirect_to_canonical_slug!(record, builder)` to issue a 301 when the
# request used a non-canonical key (integer id, legacy slug, etc.). The
# block builds the canonical path from the record so each controller
# stays declarative about its own URL helpers.
#
# Returns true when a redirect was issued (the action should `return`),
# false otherwise.
module FriendlyRedirect
  extend ActiveSupport::Concern

  private

  def redirect_to_canonical_slug!(record, &builder)
    return false unless request.get? || request.head?

    canonical = builder.call(record)
    return false if canonical.blank?
    return false if request.path == canonical

    redirect_to canonical, status: :moved_permanently
    true
  end
end
