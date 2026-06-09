# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builds the mutated payload for a game-enhanced event when the user
      # requests similar-game or channel recommendations.
      #
      # The builder renders score-bar segment rows, reconstructs the enhanced
      # message body (preserving the intro paragraph), and returns a new
      # string-keyed payload ready for a Result::Mutation.
      #
      # The caller is responsible for resolving recommendations and passing the
      # results array and result type to this builder.
      module EnhancedSegments
        extend Pito::MessageBuilder::Helpers
        module_function

        # @param event          [Event]    the original game-enhanced event.
        # @param game           [::Game]   the game for this enhanced message.
        # @param results        [Array]    Pito::Recommendation::GameSimilarity::Result or
        #                                  Game::ChannelRecommendation::Result items.
        # @param result_type    [Symbol]   :similar or :channel.
        # @param original_handle [String]  the reply_handle from the original event.
        # @return [Hash] string-keyed payload for a mutation.
        def call(event:, game:, results:, result_type:, original_handle:)
          empty_copy_key =
            case result_type
            when :similar  then "pito.copy.games.similar_empty"
            when :channel  then "pito.copy.games.channel_empty"
            end

          segments_html =
            if results.empty?
              empty_html(Pito::Copy.render(empty_copy_key, { title: game.title }))
            else
              results.map { |r| segment_html(r, result_type) }.join
            end

          rebuild_payload(event, game, segments_html, original_handle)
        end

        # ── private helpers ────────────────────────────────────────────────────

        def segment_html(result, result_type)
          score_html = render_component(Pito::ScoreBarComponent.new(score: result.score))
          display    =
            case result_type
            when :similar then ERB::Util.html_escape(result.game.title)
            when :channel
              raw = result.channel.handle.presence || result.channel.title.to_s
              ERB::Util.html_escape(raw)
            end
          <<~HTML.strip
            <div class="flex gap-2 items-center pito-game-enhanced-row">
              <span class="text-fg">#{display}</span>#{score_html}
            </div>
          HTML
        end

        def empty_html(text)
          text_esc = ERB::Util.html_escape(text)
          %(<div class="text-fg-dim pito-game-enhanced-empty">#{text_esc}</div>)
        end

        # Rebuild the enhanced message payload, replacing/adding the segments area.
        # Retains reply_handle, reply_target, and game_id; does NOT set
        # reply_consumed so the message remains chainable.
        def rebuild_payload(event, game, segments_html, original_handle)
          payload    = event.payload.with_indifferent_access
          intro_html = extract_intro_html(payload[:body].to_s)
          body       = %(<div class="pito-game-enhanced-message">#{intro_html}#{segments_html}</div>)

          {
            "body"         => body,
            "html"         => true,
            "game_id"      => game.id,
            "reply_handle" => original_handle,
            "reply_target" => "game_enhanced"
            # reply_consumed deliberately omitted — stays chainable/repliable
          }
        end

        # Extract the intro paragraph from the original enhanced body.
        # The intro is a <p class="text-fg mb-2"> rendered by GameImportJob.
        def extract_intro_html(body)
          # Strip outer wrapper div if present
          inner = body.match(/<div class="pito-game-enhanced-message">(.*)<\/div>\z/m)&.captures&.first || body
          # Return only the intro paragraph (everything up to the first segment div).
          # If no prior segments, inner IS the intro.
          inner.match(/\A(<p[^>]*>.*?<\/p>)/m)&.captures&.first || inner
        end
      end
    end
  end
end
