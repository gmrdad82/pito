# Phase 14 §2 — Bundles controller.
#
# Full RESTful surface (`index` / `show` / `new` / `create` / `edit` /
# `update`) plus a `seed_from_igdb` member action that hydrates an
# IGDB-source bundle's membership list from the IGDB API.
#
# `bundle_type` is immutable post-create (master-agent decision #3): the
# create form exposes it; the edit form does NOT, and strong params on
# update silently drop any smuggled `bundle_type` /
# `igdb_source_type` / `igdb_source_id` fields.
#
# `destroy` is dispatched through the shared `/deletions/bundle/:ids`
# action-confirmation screen — direct DELETE on `/bundles/:id` is
# routed but redirects through the action screen, matching the
# project's "no JS confirms" rule.
class BundlesController < ApplicationController
  include FriendlyRedirect

  def index
    @bundles = Bundle.order(created_at: :desc)
  end

  def show
    @bundle = Bundle.friendly.find(params[:id])
    return if redirect_to_canonical_slug!(@bundle) { |b| bundle_path(b) }

    @members = @bundle.bundle_members.includes(:game).order(:position)
  end

  def new
    @bundle = Bundle.new(bundle_type: :custom)
  end

  def create
    @bundle = Bundle.new(create_params)
    if @bundle.save
      redirect_to bundle_path(@bundle), notice: "bundle created."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    @bundle = Bundle.friendly.find(params[:id])
  end

  def update
    @bundle = Bundle.friendly.find(params[:id])
    if @bundle.update(update_params)
      redirect_to bundle_path(@bundle), notice: "bundle updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # `/bundles/:id` DELETE redirects to the action-confirmation screen
  # rather than destroying immediately, matching the project's
  # destructive-action posture (no JS confirms; everything goes
  # through the shared `_action_screen` partial).
  def destroy
    @bundle = Bundle.friendly.find(params[:id])
    redirect_to deletions_path(type: "bundle", ids: @bundle.id)
  end

  # POST /bundles/:id/seed_from_igdb. Pulls IGDB-side members for the
  # bundle's `igdb_source_type` / `igdb_source_id` pair; for each
  # returned IGDB game, ensures a local Game row exists (creates one
  # with the IGDB id if missing, enqueues `GameIgdbSync`); then adds
  # any not-yet-member games to the bundle. Additive only — never
  # removes existing members.
  def seed_from_igdb
    @bundle = Bundle.friendly.find(params[:id])

    if @bundle.type_custom? || @bundle.igdb_source_type.blank? || @bundle.igdb_source_id.blank?
      redirect_to bundle_path(@bundle),
                  alert: "no IGDB source configured."
      return
    end

    igdb_games =
      begin
        fetch_igdb_seed_games(@bundle)
      rescue Igdb::Client::Error => e
        @bundle.update_columns(last_error: "seed: #{e.message}",
                               updated_at: Time.current)
        redirect_to bundle_path(@bundle), alert: "igdb error: #{e.message}",
                    status: :see_other
        return
      end

    added = 0
    igdb_games.each do |g|
      igdb_id = g["id"].to_i
      next unless igdb_id.positive?

      game = Game.find_by(igdb_id: igdb_id)
      if game.nil?
        game = Game.new(igdb_id: igdb_id, title: g["name"].presence || "Untitled game")
        next unless game.save
        GameIgdbSync.perform_async(game.id)
      end

      next if @bundle.bundle_members.exists?(game_id: game.id)
      @bundle.bundle_members.create!(game_id: game.id)
      added += 1
    end

    @bundle.update_columns(last_error: nil, updated_at: Time.current)
    redirect_to bundle_path(@bundle),
                notice: "seeded #{added} member#{'s' if added != 1} from igdb."
  end

  private

  def create_params
    permitted = params.require(:bundle).permit(:name, :bundle_type,
                                               :igdb_source_type,
                                               :igdb_source_id)
    # Coerce blank strings to nil so the validation reads "no IGDB
    # source" rather than "blank string".
    [ :igdb_source_type, :igdb_source_id ].each do |k|
      permitted[k] = nil if permitted[k].blank?
    end
    permitted
  end

  # `bundle_type`, `igdb_source_type`, `igdb_source_id` are immutable
  # post-create — strong params drop any smuggled values silently.
  def update_params
    params.require(:bundle).permit(:name)
  end

  def fetch_igdb_seed_games(bundle)
    client = Igdb::Client.new
    case bundle.igdb_source_type
    when "franchise"
      client.fetch_games_for_franchise(bundle.igdb_source_id.to_i)
    when "source_collection"
      client.fetch_games_for_collection(bundle.igdb_source_id.to_i)
    when "source_genre"
      client.fetch_games_for_genre(bundle.igdb_source_id.to_i)
    else
      []
    end
  end
end
