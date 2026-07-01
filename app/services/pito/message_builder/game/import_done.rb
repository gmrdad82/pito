# frozen_string_literal: true

module Pito
  module MessageBuilder
    module Game
      # Builds the :enhanced "done" payload for the import flow. Two rows (19.3):
      #   1. Witty intro (inline timestamp via ts-slot) with a shimmered title and
      #      a CLICKABLE #id — clicking it prefills the chatbox with "show game #id"
      #      and submits (Enter), via the pito--chat-prefill controller.
      #   2. "A new adventure awaits." (or similar from copy pool).
      # (The old 3rd "Type `show game` to see it in full." row + its copy dictionary
      # were removed — the clickable #id makes it redundant.)
      # Repliable with reply_target: "game_imported" (show-only).
      module ImportDone
        extend Pito::MessageBuilder::Helpers
        module_function

        # Sentinel swapped into the interpolated copy for the clickable #id token.
        # A private-use codepoint that never appears in copy and survives
        # html-escaping unchanged, so it can be substituted post-render.
        ID_MARK = ""

        # @param game         [::Game]
        # @param conversation [Conversation]
        # @return [Hash] enhanced event payload (body html + html: true + game_id + follow-up fields)
        def call(game, conversation:)
          intro = Pito::Copy.render_html(
            "pito.copy.games.import_done.intro",
            { title: game.title, id: ID_MARK },
            shimmer: [ :title ]
          ).to_str.sub(ID_MARK, clickable_id_token(game)).html_safe

          adventure = Pito::Copy.render("pito.copy.games.import_done.adventure")

          body = [
            # Leading ts-slot → the timestamp sits on the SAME row as the copy (19.3).
            %(<div class="text-fg"><span data-pito-ts-slot></span>#{intro}</div>),
            %(<div class="text-fg">#{ERB::Util.html_escape(adventure)}</div>)
          ].join

          payload = html_payload(body: body, game_id: game.id)
          Pito::FollowUp.make_followupable!(payload, target: "game_imported", conversation: conversation)
          payload
        end

        # A clickable "#id" token (action-shimmer) that, on click, prefills the
        # chatbox with "show game #id" and submits it (Enter) — the exact behavior
        # the owner asked for (19.3). Reuses Pito::Shimmer::TokenComponent's
        # clickable class + prefill data so it matches every other clickable token.
        def clickable_id_token(game)
          token = "##{game.id}"
          ActionController::Base.helpers.tag.span(
            token,
            class: Pito::Shimmer::TokenComponent.css_class(token, clickable: true),
            data:  Pito::Shimmer::TokenComponent.prefill_data("show game #{token}", submit: true)
          ).to_str
        end
      end
    end
  end
end
