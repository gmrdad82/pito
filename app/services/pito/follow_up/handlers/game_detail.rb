# frozen_string_literal: true

module Pito
  module FollowUp
    module Handlers
      # Follow-up handler for game-detail events (reply_target: "game_detail").
      #
      # The detail message is stamped `reply_target: "game_detail"` by
      # `Pito::MessageBuilder::Game::Detail.call`. The user can reply:
      #
      #   #<handle> rm / delete
      #     → Delegated to Chat::Handlers::Delete via VerbDelegator.
      #
      #   #<handle> reindex
      #     → Delegated to Chat::Handlers::Reindex via VerbDelegator. The
      #       follow-up context provides the game_id so Reindex resolves the
      #       game without a ref. Emits a Voyage re-embed confirmation.
      #
      #   #<handle> link [to] [video] <id|title>
      #     → Delegated to Chat::Handlers::Link via VerbDelegator. The handler
      #       reads game_id from the source event and the video ref from rest.
      #
      #   #<handle> footage [update] <hours>
      #     → Set this game's total footage hours (ceil'd UP to the next 0.5),
      #       mirroring the `footage update <id> <hours>` chat verb (the id is
      #       implied by the card). Reachable via shift+r, which seeds `#<handle> `.
      class GameDetail < Pito::FollowUp::Handler
        self.target "game_detail"

        # @param event        [Event]        the game-detail event.
        # @param rest         [String]       text after `#<handle> `.
        # @param conversation [Conversation] the owning conversation.
        # @return [Result::Append | Result::Error]
        def call(event:, rest:, conversation:, period: nil, viewport_width: nil, channel: nil)
          action, args = parse_rest(rest)

          if %w[rm del delete reindex link unlink platform shinies sync].include?(action)
            return Pito::FollowUp::VerbDelegator.call(source_event: event, rest:, conversation:, period:, viewport_width:, channel:)
          end

          case action
          when "analyze"
            # Analyze THIS game (the detail card's single entity).
            Pito::FollowUp::AnalyzeReply.append(
              level: :game, ids: [ event.payload["game_id"] ].compact, conversation:, period:
            )
          when "footage"
            handle_footage(event, args, conversation)
          when "price"
            handle_price(event, args, conversation)
          else
            Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.game_detail.errors.invalid_action",
              message_args: { action: action }
            )
          end
        end

        private

        # ── footage [update] <hours> | footage snippet ───────────────────────────

        # `#<handle> footage [update] <hours>` sets the game's footage total (id
        # implied by the card); `#<handle> footage snippet` renders the copyable
        # ffprobe one-liner — parity with the `footage` chat verb's two forms.
        def handle_footage(event, args, conversation)
          # snippet is game-agnostic (mirrors the chat `footage snippet` form).
          if args.to_s.strip.downcase.start_with?("snippet")
            return Pito::FollowUp::Result::Append.new(
              events: [ { kind: :system, payload: Pito::MessageBuilder::Footage::Snippet.call } ]
            )
          end

          game = resolve_game_from_event(event)
          return game_not_found_error if game.nil?

          hours = parse_footage_hours(args)
          if hours.nil?
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.game_detail.errors.missing_hours",
              message_args: {}
            )
          end

          game.update!(footage_hours: hours)

          Pito::FollowUp::Result::Append.new(
            events: [ { kind: :system, payload: Pito::MessageBuilder::Text.call(
              "pito.copy.footage.updated",
              game:  game.title,
              hours: Pito::Formatter::FootageHours.call(game.footage_hours)
            ) } ]
          )
        end

        # Parse the `footage` args tail into footage hours, ceil'd UP to the next
        # 0.5 (1800 s = 0.5 h) via the shared Pito::Games::FootageAmount parser
        # (the same one the `:footage_hours` reply resolver wraps — one canonical
        # parse, no fork). Tolerates an optional leading `update` token.
        def parse_footage_hours(args)
          Pito::Games::FootageAmount.parse(args)
        end

        # ── price [set] <amount> | price unset ────────────────────────────────────

        # `#<handle> price set <amount>` / bare `#<handle> price <amount>` set the
        # game's euro price (>= 0; an explicit 0 = free, the star); `#<handle> price
        # unset` clears it to NULL. The game is known from the segment, mirroring
        # the `price` chat verb.
        def handle_price(event, args, _conversation)
          game = resolve_game_from_event(event)
          return game_not_found_error if game.nil?

          tokens = args.to_s.strip.split(/\s+/)
          sub    = tokens.first&.downcase

          if sub == "unset"
            game.update!(price: nil)
            return price_append(Pito::MessageBuilder::Text.call("pito.copy.price.unset", game: game.title))
          end

          amount = parse_price_amount(sub == "set" ? tokens[1] : tokens.first)
          if amount.nil?
            return Pito::FollowUp::Result::Error.new(
              message_key:  "pito.follow_up.game_detail.errors.missing_price",
              message_args: {}
            )
          end

          game.update!(price: amount)
          price_append(Pito::MessageBuilder::Text.call(
            "pito.copy.price.updated", game: game.title, price: Pito::Formatter::Price.call(game.price)
          ))
        end

        # Parse a euro amount (BigDecimal, 2 decimals, non-negative — 0 = free), or
        # nil — via the shared Pito::Games::PriceAmount parser (the same one the
        # `:price_amount` reply resolver wraps — one canonical parse, no fork).
        def parse_price_amount(raw)
          Pito::Games::PriceAmount.parse(raw)
        end

        def price_append(payload)
          Pito::FollowUp::Result::Append.new(events: [ { kind: :system, payload: payload } ])
        end

        # ── helpers ────────────────────────────────────────────────────────────

        # Resolve the game from the event payload.
        # DetailMessage stamps `game_id` into the payload.
        def resolve_game_from_event(event)
          payload = event.payload.with_indifferent_access
          game_id = payload[:game_id]
          return nil unless game_id.present?

          ::Game.find_by(id: game_id)
        end

        def game_not_found_error
          Pito::FollowUp::Result::Error.new(
            message_key:  "pito.follow_up.game_detail.errors.game_not_found",
            message_args: {}
          )
        end
      end
    end
  end
end
