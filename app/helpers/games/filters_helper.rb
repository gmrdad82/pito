# Phase 27 §01b — Filter row helper.
#
# Mixed into `GamesController` and exposed to views. Provides the URL
# param parser/serializer for `?filters=token1,token2` plus the chip-
# label boundary (`not_owned` → `not owned`).
#
# Surface (locked by spec §"Helper — Games::FiltersHelper"):
#
#   parse_filter_tokens(raw)   → canonical recognised tokens, de-duped,
#                                preserving input order; unknown dropped.
#   parse_dropped_tokens(raw)  → unrecognised tokens (dev-mode warning,
#                                request-spec assertions).
#   toggle_filter(active, t)   → returns a new array with `t` toggled
#                                in or out of `active`.
#   chip_label(token)          → canonical → on-screen label.
#
# No side-effects, no DB access, no Rails-cache access.
module Games
  module FiltersHelper
    # Accepts a raw `params[:filters]` value: a String (`"ps5,owned"`),
    # nil, or an Array (Rails coerces `?filters[]=ps5` into an Array).
    # Returns the canonical recognised tokens preserved in input order,
    # de-duped, unknowns dropped.
    def parse_filter_tokens(raw)
      tokens_for(raw).select { |t| Games::Filter::CANONICAL_TOKENS.include?(t) }
    end

    # Mirror of `parse_filter_tokens` returning the tokens that fell
    # outside the canonical whitelist.
    def parse_dropped_tokens(raw)
      tokens_for(raw).reject { |t| Games::Filter::CANONICAL_TOKENS.include?(t) }
    end

    # Returns a new array with `token` toggled. Order: when adding,
    # appended at the end so chip-href computation is deterministic
    # and click-order matches URL order.
    def toggle_filter(active_tokens, token)
      list = Array(active_tokens).dup
      if list.include?(token)
        list - [ token ]
      else
        list + [ token ]
      end
    end

    # On-screen label boundary. Underscored tokens (`not_owned`) split
    # to a visible space, and platform tokens carry their canonical
    # mixed-case marketing name (`PS5`, `Switch2`, `Steam`, `GoG`,
    # `Epic`, `Xbox`). Underlying URL tokens stay lowercase / underscored.
    CHIP_LABELS = {
      "not_owned" => "not owned",
      "ps5"       => "PS5",
      "switch2"   => "Switch2",
      "steam"     => "Steam",
      "gog"       => "GoG",
      "epic"      => "Epic",
      "xbox"      => "Xbox"
    }.freeze

    def chip_label(token)
      CHIP_LABELS.fetch(token.to_s, token.to_s)
    end

    private

    # Normalisation: split CSV (or accept an Array as-is), downcase,
    # strip, drop empties, de-dupe — preserving input order.
    def tokens_for(raw)
      list =
        case raw
        when Array  then raw
        when String then raw.split(",")
        when nil    then []
        else raw.to_s.split(",")
        end
      list.map { |t| t.to_s.downcase.strip }.reject(&:empty?).uniq
    end
  end
end
