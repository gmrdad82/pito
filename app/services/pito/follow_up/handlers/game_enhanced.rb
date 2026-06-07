# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for game-enhanced events (reply_target: "game_enhanced").
      #
      # The enhanced message is stamped `reply_target: "game_enhanced"` by
      # `GameImportJob` after the full 5-step import flow. The user can reply:
      #
      #   #<handle> reindex
      #     → Emit a confirmation event (`command: "game_reindex"`) whose executor
      #       branch calls `Game::VoyageIndexer.call(game, force: true)`.
      #       Mode: append — the confirmation lands as a new event below the card.
      #
      #   #<handle> similar [filters]
      #     → Parse optional `key=value` filters (genre/year/developer/publisher/
      #       platform/score/ttb/complexity), call `Pito::Recommendations.similar_games`,
      #       render a ScoreBarComponent segment per hit, and MUTATE the enhanced
      #       message body to show the results. Does NOT consume (chainable; running
      #       `channel` next swaps/updates the segment area).
      #
      #   #<handle> channel
      #     → `Pito::Recommendations.channels_for(game)`, render a ScoreBarComponent
      #       per channel result, and MUTATE the enhanced message body.
      #       Also chainable (running `similar` after `channel` works).
      #
      # == Mode
      #
      # Declared as `:mutate`.  The `reindex` action returns `Result::Append`
      # directly — the dispatch job inspects the result type and dispatches
      # accordingly.
      #
      # == Chaining
      #
      # Both `similar` and `channel` retain `reply_handle` + `reply_target` and
      # do NOT set `reply_consumed`, so the message stays repliable after each
      # call. Running `similar` after `channel` (or vice-versa) replaces the
      # rendered segment area. The `game_id` is also preserved in each mutation
      # payload so subsequent calls can still resolve the game.
      #
      # NAMESPACE GOTCHA: Inside Pito::FollowUp::Handlers::*, the bare constant
      # `Game` resolves to the Pito::Game MODULE (not the ActiveRecord model).
      # Always use `::Game` for the model and `::Game::VoyageIndexer` for the
      # indexer.
      class GameEnhanced < Pito::FollowUp::Handler
        self.target "game_enhanced"
        self.mode   :mutate
        self.actions "reindex", "similar", "channel"

        # Key-value filter tokens accepted by `similar [filters]`.
        # Maps the user-facing key (or alias) to the canonical key expected by
        # `Pito::Recommendations.similar_games(game, filters:)`.
        FILTER_KEY_MAP = {
          "genre"       => :genre,
          "year"        => :year,
          "developer"   => :developer,
          "publisher"   => :publisher,
          "platform"    => :platform,
          "score"       => :score,
          "ttb"         => :ttb,
          "complexity"  => :complexity
        }.freeze

        # @param event        [Event]        the game-enhanced event.
        # @param rest         [String]       text after `#<handle> `.
        # @param conversation [Conversation] the owning conversation.
        # @return [Result::Append | Result::Mutation | Result::Error]
        def call(event:, rest:, conversation:)
          action, args = parse_rest(rest)

          game = resolve_game_from_event(event)
          if game.nil?
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.game_enhanced.errors.game_not_found",
              message_args: {}
            )
          end

          case action
          when "reindex"
            handle_reindex(event, game, conversation)
          when "similar"
            handle_similar(event, game, args, conversation)
          when "channel"
            handle_channel(event, game, conversation)
          else
            Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.game_enhanced.errors.invalid_action",
              message_args: { action: action }
            )
          end
        end

        private

        # ── reindex ────────────────────────────────────────────────────────────

        def handle_reindex(event, game, conversation)
          payload = Pito::MessageBuilder::Game::ReindexConfirmation.call(game, conversation:)

          Pito::FollowUp::Result::Append.new(
            events: [ { kind: "confirmation", payload: payload } ]
          )
        end

        # ── similar [filters] ──────────────────────────────────────────────────

        def handle_similar(event, game, args, conversation)
          filters = parse_filters(args)
          results = Pito::Recommendations.similar_games(game, filters: filters)

          original_handle = event.payload["reply_handle"].to_s

          segments_html =
            if results.empty?
              empty_html(Pito::Copy.render("pito.copy.games.similar_empty", { title: game.title }))
            else
              results.map { |r| similar_game_segment_html(r) }.join
            end

          new_payload = rebuild_enhanced_payload(event, game, segments_html, original_handle)

          Pito::FollowUp::Result::Mutation.new(kind: "system", payload: new_payload)
        end

        # ── channel ────────────────────────────────────────────────────────────

        def handle_channel(event, game, conversation)
          results = Pito::Recommendations.channels_for(game)

          original_handle = event.payload["reply_handle"].to_s

          segments_html =
            if results.empty?
              empty_html(Pito::Copy.render("pito.copy.games.channel_empty", { title: game.title }))
            else
              results.map { |r| channel_segment_html(r) }.join
            end

          new_payload = rebuild_enhanced_payload(event, game, segments_html, original_handle)

          Pito::FollowUp::Result::Mutation.new(kind: "system", payload: new_payload)
        end

        # ── helpers ────────────────────────────────────────────────────────────

        def resolve_game_from_event(event)
          payload = event.payload.with_indifferent_access
          game_id = payload[:game_id]
          return nil unless game_id.present?

          ::Game.find_by(id: game_id)
        end

        # Parse `key=value` tokens from the filter string.
        # Unrecognised keys are silently ignored (future-proof per Recommendations doc).
        # "similar genre=action year=2020 score=70" → { genre: "action", year: "2020", score: "70" }
        def parse_filters(args)
          return {} if args.blank?

          args.to_s.scan(/(\w+)=(\S+)/).each_with_object({}) do |(raw_key, value), hash|
            canonical = FILTER_KEY_MAP[raw_key.downcase]
            hash[canonical] = value if canonical
          end
        end

        # Render a single similar-game row: ScoreBarComponent + title.
        def similar_game_segment_html(result)
          score_html = ApplicationController.renderer.render(
            Pito::ScoreBarComponent.new(score: result.score),
            layout: false
          )
          title_esc  = ERB::Util.html_escape(result.game.title)
          <<~HTML.strip
            <div class="flex gap-2 items-center pito-game-enhanced-row">
              <span class="text-fg">#{title_esc}</span>#{score_html}
            </div>
          HTML
        end

        # Render a single channel row: ScoreBarComponent + channel handle/title.
        def channel_segment_html(result)
          score_html = ApplicationController.renderer.render(
            Pito::ScoreBarComponent.new(score: result.score),
            layout: false
          )
          display    = result.channel.handle.presence || result.channel.title.to_s
          display_esc = ERB::Util.html_escape(display)
          <<~HTML.strip
            <div class="flex gap-2 items-center pito-game-enhanced-row">
              <span class="text-fg">#{display_esc}</span>#{score_html}
            </div>
          HTML
        end

        # Witty empty-state segment.
        def empty_html(text)
          text_esc = ERB::Util.html_escape(text)
          %(<div class="text-fg-dim pito-game-enhanced-empty">#{text_esc}</div>)
        end

        # Rebuild the enhanced message payload, replacing/adding the segments area.
        # Retains `reply_handle`, `reply_target`, and `game_id`; does NOT set
        # `reply_consumed` so the message remains chainable.
        def rebuild_enhanced_payload(event, game, segments_html, original_handle)
          # Re-use the original intro body from the event so it renders identically.
          payload = event.payload.with_indifferent_access

          # The original body is a <div class="pito-game-enhanced-message"> wrapper.
          # We re-wrap the intro (first child) + the new segments under the same wrapper.
          intro_html = payload[:body].to_s
            .then { |b| b[/(<div class="pito-game-enhanced-message">)(.*)/m, 0] || b }
            .then { |b| extract_intro_html(b) }

          body = %(<div class="pito-game-enhanced-message">#{intro_html}#{segments_html}</div>)

          {
            "body"        => body,
            "html"        => true,
            "game_id"     => game.id,
            "reply_handle" => original_handle,
            "reply_target" => "game_enhanced"
            # reply_consumed deliberately omitted — stays chainable/repliable
          }
        end

        # Extract the intro paragraph from the original enhanced body.
        # The intro is a <p class="text-fg mb-2"> rendered by GameImportJob#enhanced_body.
        def extract_intro_html(body)
          body.to_s.then do |b|
            # Strip outer wrapper div if present
            inner = b.match(/<div class="pito-game-enhanced-message">(.*)<\/div>\z/m)&.captures&.first || b
            # Return only the intro paragraph (everything up to the first segment div)
            # If there are no prior segments, inner IS the intro. If there are segments
            # (from a previous similar/channel call), strip them and keep only the <p>.
            intro = inner.match(/\A(<p[^>]*>.*?<\/p>)/m)&.captures&.first || inner
            intro
          end
        end
      end
    end
  end
end
