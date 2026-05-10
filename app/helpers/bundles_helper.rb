# Phase 14 §2 — Bundles view helpers.
module BundlesHelper
  # Member-picker dropdown options for the bundle show page's
  # `[ add member ]` form. Returns every Game NOT already a member of
  # `bundle`, ordered by title. Master-agent decision #4: the picker
  # source is the local Game library (NOT IGDB live search). If the
  # user wants an IGDB game they don't own, they add it via the
  # Spec 01 add-game flow first.
  def member_picker_options(bundle)
    existing_ids = bundle.bundle_members.pluck(:game_id)
    Game.where.not(id: existing_ids).order(:title).pluck(:title, :id)
  end
end
