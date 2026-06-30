# frozen_string_literal: true

module Pito
  module Event
    class ThinkingComponent < ViewComponent::Base
      # How long (seconds) each cycled verb stays on screen before the next one.
      # Single source of truth: the server uses it to pick the final (resolved)
      # word from elapsed time, and the client reads it (as ms, via a data value)
      # to drive the cycling timer — so JS never hardcodes the interval.
      INTERVAL_SECONDS = 5

      # Decorative funny glyphs shown in the resolved state (where the braille
      # spinner was). Not in Pito::Copy — these are visual symbols, not translatable
      # copy, and the Copy dictionary guard requires 1 or ≥50 variants per key.
      GLYPHS = [
        '\o/', '¯\_(ツ)_/¯', "(⌐■_■)", "o7", '\m/', "^_^", "(•‿•)", ":3", ">_<", "( •_•)>⌐■-■"
      ].freeze

      # The verb shown after `elapsed_seconds` is the `order`-th index for the
      # step we're on. Shared by the server (initial render + resolve) and
      # mirrored by the Stimulus controller so the cycled word and the final
      # past-tense word always agree.
      def self.word_index_at(order:, elapsed_seconds:)
        return 0 if order.blank?

        steps = elapsed_seconds.to_i / INTERVAL_SECONDS
        order[steps % order.length]
      end

      # @param payload [Hash] event payload with
      #   `{ dictionary:, order:, started_at:, resolved:, elapsed_seconds:, word_index: }`.
      #   `order` is a shuffled list of indices into the dictionary's `doing`
      #   array; `word_index` is only set on resolve (the last word shown).
      # @param event [Event] the persisted event (used for timestamp, turn state).
      def initialize(payload: {}, event: nil)
        payload            = payload.with_indifferent_access if payload.respond_to?(:with_indifferent_access)
        @payload           = payload
        @event             = event
        @dictionary        = payload[:dictionary].to_s
        @word_index        = payload[:word_index].to_i
        @order             = Array(payload[:order]).map(&:to_i)
        @order             = [ @word_index ] if @order.empty?
        @started_at        = payload[:started_at]
        @resolved          = payload[:resolved] == true || payload[:resolved] == "true"
        @elapsed_seconds   = payload[:elapsed_seconds]
      end

      def resolved?
        @resolved
      end

      def resolved_message
        return nil unless resolved?

        word    = done_word
        elapsed = format_elapsed(@elapsed_seconds)
        I18n.t("pito.event.thinking.resolved", word:, elapsed:)
      end

      # Picks a glyph from GLYPHS deterministically so the same resolved event
      # always shows the same glyph across re-renders. Seeded from the persisted
      # event id (or for_event_id from the payload, or word_index as last resort)
      # so the selection is stable without storing anything extra in the payload.
      def resolved_glyph
        return nil unless resolved?

        seed = (@event&.id || @payload[:for_event_id]&.to_i || @word_index).to_i
        GLYPHS[seed.abs % GLYPHS.size]
      end

      def braille_frames_json
        Pito::Event::Concerns::BrailleFrames::FRAMES.to_json
      end

      def doing_words_json
        doing_words.to_json
      end

      def done_words_json
        Array(I18n.t("pito.copy.thinking.#{@dictionary}.done")).to_json
      end

      def order_json
        @order.to_json
      end

      # started_at as epoch milliseconds, so the client can compare against
      # `Date.now()` regardless of timezone.
      def started_at_ms
        return 0 unless @started_at

        (Time.parse(@started_at.to_s).to_f * 1000).round
      rescue ArgumentError
        0
      end

      def interval_ms
        INTERVAL_SECONDS * 1000
      end

      # The verb to show right now (pre-JS / no-JS render), derived from how long
      # the turn has been running — keeps the server render in sync with the
      # client's cycling and survives a refresh.
      def current_word
        idx = self.class.word_index_at(order: @order, elapsed_seconds: elapsed_so_far)
        doing_words[idx] || doing_words.first
      end

      def dom_id
        @event ? "event_#{@event.id}" : nil
      end

      private

      def elapsed_so_far
        return 0 unless @started_at

        [ (Time.current - Time.parse(@started_at.to_s)).to_i, 0 ].max
      rescue ArgumentError
        0
      end

      # Format an elapsed-seconds value for display: at most 2 decimal places
      # with trailing fractional zeros stripped.
      #   0.224 → "0.22",  0.5 → "0.5",  1.0 → "1",  2.47 → "2.47"
      # The persisted payload stores the full-precision float; this only
      # affects what is shown in the resolved label.
      def format_elapsed(seconds)
        return "0" if seconds.nil?

        ("%.2f" % seconds.to_f.round(2)).sub(/\.?0+\z/, "")
      end

      def doing_words
        Array(I18n.t("pito.copy.thinking.#{@dictionary}.doing"))
      end

      def done_word
        Array(I18n.t("pito.copy.thinking.#{@dictionary}.done"))[@word_index] || doing_words.first
      end
    end
  end
end
