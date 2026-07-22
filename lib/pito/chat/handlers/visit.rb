# frozen_string_literal: true

module Pito
  module Chat
    module Handlers
      # Handler for the `visit` chat tool — opens a vid's YouTube page, or a
      # channel's YouTube page / Studio, via the shimmer + auto-click flow
      # Pito::MessageBuilder::Video::Visit / Pito::MessageBuilder::Channel::Visit
      # render.
      #
      # Typed forms:
      #   visit vid <id> <destination>              — a vid, by numeric id.
      #   visit channel <id|@handle> <destination>  — a channel, by id or @handle.
      #   visit <destination>                       — bare: the SOLE connected
      #     channel (owner Q51b's single-channel handle-skippability law — the
      #     same idiom as Pito::Chat::Handlers::Shinies#resolve_channel). With
      #     zero or several channels connected, still ambiguous → the same
      #     needs_destination error a missing/unrecognised destination gets.
      #
      # <destination> vocabulary: youtube, studio, plus the synonyms yt and
      # channel (both canonicalise to "youtube"). `channel` therefore does
      # double duty — it is ALSO the noun that introduces the channel-subject
      # form above — so it only reads as that noun when immediately followed
      # by something ref-shaped (`@handle` or a numeric id); a bare `channel`,
      # or `channel` followed by anything else, is the destination synonym
      # instead (mirrors the double duty the word already carried in the old
      # follow-up-only Pito::FollowUp::Handlers::ChannelDetail::DESTINATION_MAP).
      #
      # A vid subject always renders with the canonical destination as-is
      # (:youtube/:studio — Pito::MessageBuilder::Video::Visit's own naming); a
      # channel subject maps "youtube" to the LEGACY :channel symbol —
      # Pito::MessageBuilder::Channel::Visit and every persisted channel-visit
      # payload have always used "channel", never "youtube", and that contract
      # is kept here, not renamed.
      #
      # Reply path (`#<handle> visit …`, wired by a later task's tools.yml
      # `reply.targets` declaration + Pito::FollowUp::ToolDelegator delegation):
      # the subject and destination arrive PRE-RESOLVED as bound kwargs
      # (`kwargs[:ref]`, `kwargs[:destination]`) via Pito::Dispatch::ReplyBinding
      # — no raw parsing runs. The destination value is still passed through
      # #resolve_destination so a bound "youtube" and a bound legacy "channel"
      # both normalise the same way the typed path's synonyms do.
      class Visit < Pito::Chat::Handler
        self.tool = :visit
        self.description_key = "pito.chat.visit.descriptions.visit"

        VIDEO_NOUN_FILLERS = %w[vid vids video videos].freeze
        CHANNEL_NOUN = "channel"

        DESTINATION_WORDS = {
          "youtube" => "youtube",
          "yt"      => "youtube",
          "channel" => "youtube",
          "studio"  => "studio"
        }.freeze

        def call
          return follow_up_visit if follow_up?

          parse_typed
        end

        private

        # ── Reply path (bound kwargs — see class header) ────────────────────────

        def follow_up_visit
          subject = kwargs[:ref]
          return not_found if subject.nil?

          destination = resolve_destination(kwargs[:destination])
          return needs_destination if destination.nil?

          visit_event(subject, destination)
        end

        # ── Typed-chat path ──────────────────────────────────────────────────────

        def parse_typed
          body = message.raw.to_s.strip.sub(/\A\S+\s*/, "") # drop the tool word
          return needs_destination if body.blank?

          words = body.split(/\s+/)
          first = words.first.downcase

          if VIDEO_NOUN_FILLERS.include?(first)
            video_form(words.drop(1))
          elsif first == CHANNEL_NOUN && channel_ref_follows?(words)
            channel_form(words.drop(1))
          else
            bare_form(words)
          end
        end

        # `channel <ref> <destination>` only when the SECOND word looks like a
        # ref (`@handle` or a numeric/`#`-prefixed id) — otherwise `channel` is
        # the bare destination synonym (see class header).
        def channel_ref_follows?(words)
          ref = words[1].to_s
          return false if ref.blank?

          ref.start_with?("@") || ref.sub(/\A#\s*/, "").match?(/\A\d+\z/)
        end

        def video_form(words)
          destination = resolve_destination(words[1])
          return needs_destination if destination.nil?

          ref   = words[0].to_s
          video = find_video(ref)
          return not_found(ref) if video.nil?

          visit_event(video, destination)
        end

        def channel_form(words)
          destination = resolve_destination(words[1])
          return needs_destination if destination.nil?

          ref               = words[0].to_s
          resolved_channel  = find_channel(ref)
          return not_found(ref) if resolved_channel.nil?

          visit_event(resolved_channel, destination)
        end

        # Bare `visit <destination>` (no subject at all) → the SOLE connected
        # channel. More than one word here means neither the vid-noun nor the
        # channel-ref form matched, so only a single recognised destination
        # word counts — anything else is unrecognised.
        def bare_form(words)
          return needs_destination unless words.size == 1

          destination = resolve_destination(words.first)
          return needs_destination if destination.nil?

          sole = ::Channel.sole
          return needs_destination if sole.nil?

          visit_event(sole, destination)
        end

        # ── Shared resolution ────────────────────────────────────────────────────

        def resolve_destination(word)
          DESTINATION_WORDS[word.to_s.downcase]
        end

        def find_video(ref)
          id = ref.to_s.sub(/\A#\s*/, "")
          return nil unless id.match?(/\A\d+\z/)

          ::Video.find_by(id: id)
        end

        def find_channel(ref)
          str = ref.to_s
          id  = str.sub(/\A#\s*/, "")
          return ::Channel.find_by(id: id) if id.match?(/\A\d+\z/)

          ::Channel.resolve_handle(str)
        end

        # ── Event / errors ───────────────────────────────────────────────────────

        def visit_event(subject, destination)
          payload =
            if subject.is_a?(::Video)
              Pito::MessageBuilder::Video::Visit.call(subject, conversation:, destination: destination.to_sym)
            else
              Pito::MessageBuilder::Channel::Visit.call(subject, conversation:, destination: channel_destination(destination))
            end

          Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: payload } ])
        end

        # The legacy channel-destination symbol — persisted channel-visit
        # payloads have always used "channel" (never "youtube"); kept, not renamed.
        def channel_destination(destination)
          destination == "studio" ? :studio : :channel
        end

        def needs_destination
          Pito::Chat::Result::Error.new(
            message_key:  "pito.chat.visit.errors.needs_destination",
            message_args: {}
          )
        end

        def not_found(ref = nil)
          Pito::Chat::Result::Error.new(
            message_key:  "pito.chat.visit.errors.not_found",
            message_args: { ref: ref.presence || "that" }
          )
        end
      end
    end
  end
end
