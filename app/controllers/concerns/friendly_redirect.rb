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

    # Compare the path used to address the resource (`params[:id]`) against
    # the record's canonical `to_param`. Comparing `request.path` directly
    # to the builder output would falsely fire for `.json` / other format
    # requests because `request.path` includes the format extension while
    # `model_path(record)` does not.
    return false if params[:id].to_s == record.to_param.to_s

    redirect_to canonical, status: :moved_permanently
    true
  end
end
