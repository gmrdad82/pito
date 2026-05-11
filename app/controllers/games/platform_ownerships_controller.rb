# Phase 27 §01f — Per-platform ownership editor.
#
# Routes:
#
#   GET    /games/:game_id/platform_ownerships/edit  → edit
#   PATCH  /games/:game_id/platform_ownerships       → update
#   PUT    /games/:game_id/platform_ownerships       → update
#
# Editor revamp (2026-05-12): the surface is a single bracketed
# checkbox per release-platform (plus any platform the user already
# owns the game on whose IGDB record was scrubbed later). The form
# posts a flat `platform_owned_ids[]` array; every absent platform is
# treated as "not owned". No per-row metadata fields (`acquired_at`,
# `store`, `notes` were dropped from the schema in the same patch).
#
# Friendly URL — `:game_id` carries `Game#to_param` (the IGDB slug
# when present, falls back to id).
#
# No JS confirm. Un-ticking an owned platform is part of the same
# form submit; the ownership row is a metadata join, not a top-level
# destructible record per the project's `bulk-as-foundation` rule.
module Games
  class PlatformOwnershipsController < ApplicationController
    before_action :load_game

    def edit
      @platforms = platforms_for_editor
      @owned_platform_ids = owned_platform_ids
    end

    def update
      raw_ids = Array(params[:platform_owned_ids]).reject(&:blank?)
      submitted_ids = raw_ids.map(&:to_i).uniq

      validation_error = validate_ids(submitted_ids)
      if validation_error
        @platforms = platforms_for_editor
        @owned_platform_ids = owned_platform_ids
        @form_error = validation_error
        return render :edit, status: :unprocessable_content
      end

      sync_ownerships(submitted_ids)

      redirect_to game_path(@game), notice: "ownership updated."
    rescue ActiveRecord::RecordInvalid => e
      @platforms = platforms_for_editor
      @owned_platform_ids = owned_platform_ids
      @form_error = e.record.errors.full_messages.join(", ")
      render :edit, status: :unprocessable_content
    end

    private

    def load_game
      @game = Game.friendly.find(params[:game_id])
    end

    # Union of release-platforms (sourced from IGDB) and any platform
    # the user already owns the game on (covers manually-added rows
    # whose platform was scrubbed from IGDB later). Sorted
    # alphabetically (case-insensitive).
    def platforms_for_editor
      release_platforms = @game.platforms_available.to_a
      owned_platforms = @game.game_platform_ownerships.includes(:platform).map(&:platform)
      (release_platforms + owned_platforms).uniq.sort_by { |p| p.name.to_s.downcase }
    end

    def owned_platform_ids
      @game.game_platform_ownerships.pluck(:platform_id)
    end

    def validate_ids(ids)
      return nil if ids.empty?
      if ids.size != ids.uniq.size
        return "duplicate platform submitted."
      end
      missing = ids.reject { |pid| Platform.exists?(pid) }
      return "unknown platform." if missing.any?
      nil
    end

    # Bring `game.game_platform_ownerships` into shape with the
    # submitted id list. Rows for ids in the list are kept (created
    # when missing), rows for ids NOT in the list are destroyed.
    def sync_ownerships(submitted_ids)
      existing = @game.game_platform_ownerships.to_a
      existing.each do |row|
        row.destroy! unless submitted_ids.include?(row.platform_id)
      end
      new_ids = submitted_ids - existing.map(&:platform_id)
      new_ids.each do |pid|
        @game.game_platform_ownerships.create!(platform_id: pid)
      end
    end
  end
end
