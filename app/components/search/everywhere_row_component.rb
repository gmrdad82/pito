# Phase 37 — "everywhere" omnisearch row.
#
# Standalone sibling of `Search::OmnisearchResultRowComponent`. Handles
# three row kinds in a single component because every row in the
# "everywhere" modal is a navigation link (no per-row [add] button
# action — that surface stays on the /games bundle-add modal).
#
# Kinds:
#   :game    — Game record. Title + release-year suffix + muted
#               "game" label. Link to `game_path(record)`.
#   :bundle  — Bundle record. Name + member-count suffix + muted
#               "bundle" label. Link to `bundle_path(record)`.
#   :channel — channel-shaped Hash (mock data — `:id`, `:display_name`,
#               `:handle`, `:avatar_url`, optional `:subscriber_count`).
#               Avatar (circular per design.md §"Channel avatars") +
#               display_name + @handle + muted "channel" label. Link
#               to `/channels` (the only channel surface today).
#
# Args:
#   kind:   one of :game | :bundle | :channel.
#   record: the underlying object — model for :game / :bundle, Hash
#            for :channel.
module Search
  class EverywhereRowComponent < ViewComponent::Base
    KINDS = %i[game bundle channel].freeze

    def initialize(kind:, record:)
      raise ArgumentError, "unknown row kind: #{kind.inspect}" unless KINDS.include?(kind)

      @kind = kind
      @record = record
    end

    attr_reader :kind, :record

    # Avatar tile dimension for the :channel row. Matches the chip-row
    # tile sizing in `Channels::AvatarChipComponent` (1.4em + 4px
    # overflow) so the visual rhythm stays consistent across surfaces.
    def channel_avatar_dimension_css
      "calc(1.4em + 4px)"
    end

    # Bundle member-count suffix. Bundles expose `bundle_members.size`
    # via the association; we guard for nil in case a future caller
    # passes a slim view-model.
    def bundle_member_count
      return nil unless record.respond_to?(:bundle_members)
      Array(record.bundle_members).size
    end
  end
end
