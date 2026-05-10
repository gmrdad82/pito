# Phase 15 §1 — Calendar Data Model.
#
# Orchestrator for derived calendar entries. The host model
# (Channel / Video / Game) implements the `CalendarDerivable` contract;
# this service translates host state into idempotent upserts.
#
# Upsert key is `(entry_type, source_ref)`. The race-guard partial
# unique indexes (Q17) catch concurrent inserts; we rescue the
# uniqueness violation and retry the lookup once.
#
# `metadata.user_overrides` is preserved across re-syncs — the upsert
# overwrites all other metadata keys but never the overrides sub-key.
module Calendar
  class Derivation
    class << self
      # Sync a single host. Returns the resulting CalendarEntry or nil
      # if the host's current state should NOT have a derived entry.
      def sync!(host)
        attrs = host.calendar_entry_attributes
        return revoke_all_for_host!(host) if attrs.nil?

        type = host.calendar_entry_type
        ref  = host.calendar_entry_source_ref

        existing = find_existing(type, ref)
        result =
          if existing
            upsert_existing!(existing, attrs, ref)
          else
            create_new!(type, attrs, ref, host)
          end

        # Transition cleanup: supersede any DERIVED entries tied to the
        # same host (by typed FK) that aren't this row. Catches the
        # video_scheduled → video_published flip (source_ref shapes
        # differ, so the upsert can't see them).
        supersede_other_derived!(host, result&.id)
        result
      rescue ActiveRecord::RecordNotUnique
        existing = find_existing(type, ref)
        return nil unless existing
        upsert_existing!(existing, attrs, ref)
      end

      # Revoke (supersede, NOT delete) any derived entry tied to the
      # host's current source_ref. Used when the host's state no longer
      # warrants a derived entry — e.g., a video flips back to private
      # after being scheduled, or a game's release_date is cleared.
      def revoke!(host)
        type = host.calendar_entry_type
        ref  = host.calendar_entry_source_ref
        return nil if type.nil? || ref.blank?

        rows = CalendarEntry
                 .where(entry_type: type)
                 .where("source_ref @> ?::jsonb", ref.to_json)
        rows.update_all(
          state: CalendarEntry.states[:superseded],
          updated_at: Time.current
        )
        nil
      end

      # Supersede ALL derived entries tied to a host via its typed FK,
      # regardless of source_ref shape. Used by the CalendarDerivable
      # concern when the host's current state has NO derivation (e.g.,
      # a Video flipping from public → private with no publish_at, or
      # a Game with `release_date=nil`). The previous derivation may
      # have written either a `video_published` OR a `video_scheduled`
      # row; without knowing which, we supersede every derived entry
      # linked by the host's typed FK column.
      def revoke_all_for_host!(host)
        host_class = host.class.name
        scope = case host_class
        when "Video"   then CalendarEntry.where(video_id: host.id)
        when "Channel" then CalendarEntry.where(channel_id: host.id)
        when "Game"    then CalendarEntry.where(game_id: host.id)
        else return nil
        end

        scope = scope.where(source: %i[derived auto])
                     .where.not(state: :superseded)

        scope.update_all(
          state: CalendarEntry.states[:superseded],
          updated_at: Time.current
        )
        nil
      end

      private

      def supersede_other_derived!(host, current_id)
        host_class = host.class.name
        scope = case host_class
        when "Video"   then CalendarEntry.where(video_id: host.id)
        when "Channel" then CalendarEntry.where(channel_id: host.id)
        when "Game"    then CalendarEntry.where(game_id: host.id)
        else return
        end

        scope = scope.where(source: :derived)
                     .where.not(state: :superseded)
        scope = scope.where.not(id: current_id) if current_id
        scope.update_all(
          state: CalendarEntry.states[:superseded],
          updated_at: Time.current
        )
      end

      def find_existing(type, ref)
        return nil if ref.blank?
        CalendarEntry
          .where(entry_type: type)
          .where("source_ref @> ?::jsonb", ref.to_json)
          .first
      end

      def upsert_existing!(existing, attrs, _ref)
        preserved = (existing.metadata || {})["user_overrides"] || {}
        merged_metadata = (attrs[:metadata] || {})
                            .stringify_keys
                            .merge("user_overrides" => preserved)
        new_attrs = attrs.merge(metadata: merged_metadata)
        existing.bypass_readonly = true
        existing.assign_attributes(new_attrs)
        existing.save!
        existing
      end

      def create_new!(type, attrs, ref, _host)
        merged_metadata = (attrs[:metadata] || {}).stringify_keys
        merged_metadata["user_overrides"] ||= {}
        CalendarEntry.create!(
          attrs.merge(
            entry_type: type,
            source: :derived,
            source_ref: ref,
            metadata: merged_metadata
          )
        )
      end
    end
  end
end
