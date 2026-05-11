# Phase 27 §01f — Per-platform ownership editor.
#
# Routes:
#
#   GET    /games/:game_id/platform_ownerships/edit  → edit
#   PATCH  /games/:game_id/platform_ownerships       → update
#   PUT    /games/:game_id/platform_ownerships       → update
#
# The action scaffolds in-memory `GamePlatformOwnership` rows for every
# IGDB release-platform of the game that the user does not yet own, so
# the editor renders one row per available platform. The form posts a
# nested-attributes payload with a per-row `_own` flag using the
# project's `"yes"` / `"no"` boundary convention; the controller
# translates `_own` into either a present row (yes → keep / create) or
# a `_destroy` marker (no → remove an existing row).
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
      @ownerships_by_platform = build_ownership_rows
    end

    def update
      raw_rows = params.dig(:game, :game_platform_ownerships_attributes)
      raw_rows = raw_rows.respond_to?(:to_unsafe_h) ? raw_rows.to_unsafe_h : raw_rows

      validation_error = validate_rows(raw_rows)
      if validation_error
        @ownerships_by_platform = build_ownership_rows
        @form_error = validation_error
        return render :edit, status: :unprocessable_content
      end

      nested = transform_rows(raw_rows)

      if @game.update(game_platform_ownerships_attributes: nested)
        redirect_to game_path(@game), notice: "ownership updated."
      else
        @ownerships_by_platform = build_ownership_rows
        @form_error = @game.errors.full_messages.join(", ")
        render :edit, status: :unprocessable_content
      end
    rescue ActiveRecord::RecordNotFound
      @ownerships_by_platform = build_ownership_rows
      @form_error = "one of the ownership rows was modified in another tab. " \
                    "review the editor below and try again."
      render :edit, status: :unprocessable_content
    end

    private

    def load_game
      @game = Game.friendly.find(params[:game_id])
    end

    # Build a hash keyed by Platform → ownership-row instance (persisted
    # or in-memory) so the editor renders one row per release-platform.
    # Platforms with no ownership row get an unsaved record so the form
    # can carry `_own: "no"` for them without scaffolding records
    # outside the form scope.
    def build_ownership_rows
      release_platforms = @game.platforms_available.to_a
      existing = @game.game_platform_ownerships.includes(:platform).to_a
      existing_by_platform_id = existing.index_by(&:platform_id)

      # Union: every release-platform plus any owned platform not in
      # the release set (covers manually-added ownership rows whose
      # platform was scrubbed from IGDB later).
      owned_only = existing.map(&:platform).reject { |p| release_platforms.map(&:id).include?(p.id) }
      rows = {}
      (release_platforms + owned_only).sort_by { |p| p.name.to_s.downcase }.each do |platform|
        rows[platform] = existing_by_platform_id[platform.id] ||
                         @game.game_platform_ownerships.new(platform: platform)
      end
      rows
    end

    # Reject any row whose `_own` value isn't strictly `"yes"` or
    # `"no"` (or absent — absent counts as "no"). Returns an error
    # string when a row is invalid, nil otherwise.
    def validate_rows(rows)
      return nil if rows.blank?

      entries = rows.is_a?(Hash) ? rows.values : rows
      seen_platform_ids = []

      entries.each do |row|
        next unless row.is_a?(Hash)
        own_value = row["_own"] || row[:_own]
        next if own_value.blank?
        unless YesNo.yes_no?(own_value)
          return "_own must be 'yes' or 'no'."
        end

        platform_id_raw = row["platform_id"] || row[:platform_id]
        next if platform_id_raw.blank?
        pid = platform_id_raw.to_i
        if pid <= 0 || !Platform.exists?(pid)
          return "unknown platform."
        end
        if seen_platform_ids.include?(pid)
          return "duplicate platform row submitted."
        end
        seen_platform_ids << pid
      end
      nil
    end

    # Translate the form rows into a hash AR's nested-attributes API
    # accepts. Each row carries either `_destroy: "1"` (un-tick → remove)
    # or the canonical attributes (tick → keep / create).
    def transform_rows(rows)
      return {} if rows.blank?

      entries = rows.is_a?(Hash) ? rows.values : rows
      result = {}

      entries.each_with_index do |row, idx|
        next unless row.is_a?(Hash)

        own_value = row["_own"] || row[:_own]
        owned = YesNo.from_yes_no(own_value)
        existing_id = row["id"] || row[:id]
        platform_id = row["platform_id"] || row[:platform_id]

        attrs = {}
        attrs[:id] = existing_id if existing_id.present?
        attrs[:platform_id] = platform_id if platform_id.present?
        attrs[:acquired_at] = (row["acquired_at"] || row[:acquired_at]).presence
        attrs[:store] = (row["store"] || row[:store]).presence
        attrs[:notes] = (row["notes"] || row[:notes]).presence

        if owned
          # Keep / create. AR creates when `id` is missing, updates when
          # present.
          result[idx.to_s] = attrs.compact
        elsif existing_id.present?
          # Un-tick an existing row → destroy on save.
          result[idx.to_s] = { id: existing_id, _destroy: "1" }
        end
        # Else: not owned AND no existing row → drop silently.
      end

      result
    end
  end
end
