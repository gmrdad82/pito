# frozen_string_literal: true

module Pito
  module Schedule
    # THE scheduling-proximity law (owner directive, 4.0.0):
    #
    #   1. SPACING — a new publish moment keeps at least 4 hours of air from
    #      every other scheduled OR published vid on the same channel
    #      (exactly 4h apart passes, mirroring the old 60-min rule's
    #      boundary semantics).
    #   2. DAY CAP — once the new moment lands, no rolling 24h window on the
    #      channel may hold more than 2 publishes. "Day" is deliberately a
    #      sliding 24h span, not a calendar day — the owner's own
    #      simplification, and it dodges every timezone seam.
    #
    # Scope guards live at the CALL SITES, not here: only pito-initiated
    # schedule/publish acts consult the policy (the :schedule/:publish
    # validation contexts and the handlers' stage-time dry-runs). Studio-side
    # state mirrors in freely, and pre-existing violations are grandfathered —
    # a triple that already exists on YouTube never blocks anything by
    # itself; the law gates NEW acts only (the candidate moment must be a
    # member of any triple it rejects).
    #
    # Published vids count via their mirrored `published_at`; pending
    # schedules via future `publish_at` (the `scheduled` scope). Unlisted
    # stays out of the comparison set on purpose — the owner named
    # "scheduled/published" and unlisted vids are neither.
    module SpacingPolicy
      module_function

      SPACING    = 4.hours
      DAY_WINDOW = 24.hours
      DAY_CAP    = 2

      # @param video [::Video] the vid being scheduled/published (excluded
      #   from its own comparison set).
      # @param at [Time] the candidate publish moment — future for schedule,
      #   Time.current for publish-now.
      # @param extra [Array<Hash>] staged batch siblings not yet in the DB
      #   (`{ time:, title: }`), so a mass dry-run judges each row against
      #   the rows before it.
      # @return [Hash, nil] nil when the law is satisfied, else
      #   `{ kind: :spacing, title:, at: }` (the nearest offender) or
      #   `{ kind: :day_cap, titles: [..2], at: }` (the pair that would share
      #   a 24h window with the candidate).
      def call(video:, at:, extra: [])
        return nil if at.blank? || video.channel_id.blank?

        others = neighbors(video, at) + extra.map { |e| { title: e[:title].to_s, time: e[:time] } }

        offender = others.min_by { |o| (o[:time] - at).abs }
        if offender && (offender[:time] - at).abs < SPACING
          return { kind: :spacing, title: offender[:title], at: offender[:time] }
        end

        pair = day_cap_pair(others, at)
        return { kind: :day_cap, titles: pair.map { |o| o[:title] }, at: at } if pair

        nil
      end

      # The (copy key, args) pair for a verdict — one mapping shared by the
      # stage-time dry-runs and the confirm-time rescues so single and mass
      # surfaces speak identical copy for identical verdicts.
      def copy_args(violation, title:, mass: false)
        prefix = mass ? "pito.copy.videos.mass_schedule" : "pito.copy.videos.schedule"
        if violation[:kind] == :spacing
          [ "#{prefix}_conflict",
            { title: title, other: violation[:title].to_s,
              when: Pito::Formatter::SyncStamp.call(violation[:at]) } ]
        else
          [ "#{prefix}_day_cap",
            { title: title, others: Array(violation[:titles]).join(" and ") } ]
        end
      end

      # Same-channel publish moments within the widest window either rule can
      # see (±24h): pending schedules by future publish_at, published vids by
      # their mirrored published_at.
      def neighbors(video, at)
        scope = ::Video.where(channel_id: video.channel_id).where.not(id: video.id)
        lo, hi = at - DAY_WINDOW, at + DAY_WINDOW

        scheduled = scope.scheduled.where(publish_at: lo..hi).pluck(:title, :publish_at)
        published = scope.privacy_status_public.where.not(published_at: nil)
                         .where(published_at: lo..hi).pluck(:title, :published_at)

        (scheduled + published).map { |title, time| { title: title, time: time } }
      end

      # The first pair of existing publish moments whose span TOGETHER WITH
      # the candidate fits inside one 24h window — i.e. adding the candidate
      # would put 3 publishes in a day. Pairs that violate on their own
      # without the candidate joining them are someone else's history, not
      # this act's problem.
      def day_cap_pair(others, at)
        others.combination(DAY_CAP).find do |pair|
          times = pair.map { |o| o[:time] } << at
          times.max - times.min <= DAY_WINDOW
        end
      end
    end
  end
end
