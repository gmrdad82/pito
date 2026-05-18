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
    # Phase 20 — friendly URLs. The hidden field on the add-member form
    # currently sends an integer Game id, but the boundary accepts a
    # slug too so future form refactors don't have to thread the change.
    game = begin
      Game.friendly.find(params[:game_id])
    rescue ActiveRecord::RecordNotFound
      nil
    end
    if game.nil?
      redirect_to bundle_path(@bundle), alert: "game not found.",
                  status: :see_other
      return
    end

    # 2026-05-18 — `source=games_show` opt-in: callers on /games/:id
    # (the "suggested bundles" right-half tiles, via the suggest-mode
    # `BundleTileComponent`'s `button_to`) want the redirect to land
    # back on the game show page with "added to <bundle name>." in
    # the flash, NOT on the bundle show page with "added <game title>."
    # (the steady-state behavior the bundle-show add-member form
    # depends on). Branch in one place; keep the existing flow intact
    # for every caller that does not opt in.
    from_games_show = params[:source].to_s == "games_show"
    redirect_target = from_games_show ? game_path(game) : bundle_path(@bundle)

    if @bundle.bundle_members.exists?(game_id: game.id)
      message = from_games_show ? "already in #{@bundle.name}." : "already a member."
      redirect_to redirect_target, alert: message, status: :see_other
      return
    end

    member = @bundle.bundle_members.build(game_id: game.id)
    if member.save
      message = from_games_show ? "added to #{@bundle.name}." : "added #{game.title}."
      redirect_to redirect_target, notice: message
    else
      redirect_to redirect_target,
                  alert: member.errors.full_messages.to_sentence,
                  status: :see_other
    end
  end

  # 2026-05-18 — `[add]` for IGDB rows in the bundle modal `:bundle_add`
  # omnisearch. The IGDB result is not yet in the library; this action
  # collapses the two-step (sync IGDB into the library, then add to
  # the bundle) into one click:
  #
  #   1. If a Game with the supplied `igdb_id` already exists, just
  #      add it to the bundle (idempotent against re-adding).
  #   2. Otherwise create a Game stub with `igdb_id` + optional title
  #      pre-seed (mirrors `GamesController#create`'s pattern), enqueue
  #      `GameIgdbSync` to populate the rest of the metadata, and add
  #      the new game to the bundle as a new `BundleMember`.
  #
  # Redirects back to the bundle's show page on success so the user
  # sees the new member row appear.
  def from_igdb
    igdb_id = params[:igdb_id].to_i
    if igdb_id <= 0
      redirect_to bundle_path(@bundle),
                  alert: I18n.t("games.flash.invalid_igdb_id"),
                  status: :see_other
      return
    end

    game = Game.find_by(igdb_id: igdb_id)
    if game.nil?
      title_seed = params[:title].to_s.strip[0, 255]
      attrs = { igdb_id: igdb_id }
      attrs[:title] = title_seed if title_seed.present?
      game = Game.new(attrs)
      unless game.save
        redirect_to bundle_path(@bundle),
                    alert: I18n.t("games.flash.create_failed"),
                    status: :see_other
        return
      end
      GameIgdbSync.perform_async(game.id)
    end

    if @bundle.bundle_members.exists?(game_id: game.id)
      redirect_to bundle_path(@bundle),
                  alert: "already a member.",
                  status: :see_other
      return
    end

    member = @bundle.bundle_members.build(game_id: game.id)
    if member.save
      redirect_to bundle_path(@bundle),
                  notice: "added #{game.title}."
    else
      redirect_to bundle_path(@bundle),
                  alert: member.errors.full_messages.to_sentence,
                  status: :see_other
    end
  end

  def destroy
    # Phase 20 — friendly URLs. `params[:id]` is the GAME identifier and
    # may arrive as either an integer id or a slug (`igdb_slug`).
    # Translate via `Game.friendly.find` before walking the join table.
    game = begin
      Game.friendly.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      nil
    end
    member = game && @bundle.bundle_members.find_by(game_id: game.id)
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
    @bundle = Bundle.friendly.find(params[:bundle_id])
  end
end
