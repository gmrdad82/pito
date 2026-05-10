# Phase 14 §2 — Bundle membership controller.
#
# Two actions, both dispatched from the bundle show page:
#   - `create`  — `POST /bundles/:bundle_id/members` with
#                  `params[:game_id]`. Adds the game to the bundle
#                  (insertion-order position via the `BundleMember`
#                  before_validation hook). Enqueues
#                  `BundleCoverBuild` via the model's after_create_commit.
#                  Idempotent: re-adding an existing member surfaces a
#                  flash alert; no exception.
#   - `destroy` — `DELETE /bundles/:bundle_id/members/:id` where `:id`
#                  is the GAME id (not the BundleMember id) per the
#                  spec's URL shape. Removes the join row; the model's
#                  after_destroy_commit enqueues `BundleCoverBuild`.
#
# Both actions redirect back to the bundle show page on success.
class BundleMembersController < ApplicationController
  before_action :load_bundle

  def create
    game = Game.find_by(id: params[:game_id])
    if game.nil?
      redirect_to bundle_path(@bundle), alert: "game not found.",
                  status: :see_other
      return
    end

    if @bundle.bundle_members.exists?(game_id: game.id)
      redirect_to bundle_path(@bundle), alert: "already a member.",
                  status: :see_other
      return
    end

    member = @bundle.bundle_members.build(game_id: game.id)
    if member.save
      redirect_to bundle_path(@bundle), notice: "added #{game.title}."
    else
      redirect_to bundle_path(@bundle),
                  alert: member.errors.full_messages.to_sentence,
                  status: :see_other
    end
  end

  def destroy
    member = @bundle.bundle_members.find_by(game_id: params[:id])
    if member.nil?
      redirect_to bundle_path(@bundle), alert: "member not found.",
                  status: :see_other
      return
    end

    member.destroy!
    redirect_to bundle_path(@bundle), notice: "removed."
  end

  private

  def load_bundle
    @bundle = Bundle.find(params[:bundle_id])
  end
end
