# frozen_string_literal: true

# Spec helper for the dispatcher-grammar suite (Phase D).
#
# `parsed_intent(input)` resolves what the system UNDERSTANDS a raw input to be,
# WITHOUT executing any handler or touching the database. It mirrors the live
# routing decisions:
#
#   1. SHAPE  — leading `/` → :slash, leading `#` → :hashtag, else → :chat
#               (the `chat_controller` contract: `input.start_with?("/") ? :slash …`).
#   2. TOOL   — chat:    token → grammar spec (alias-aware) → canonical → handler class
#               slash:   token → grammar spec (alias-aware) → name + auth
#               hashtag: parse `#handle action rest` (target→handler is DB-bound, so
#                        only the parse + per-target action gating are asserted here).
#
# Returned Hash (symbol keys), by stack:
#   :chat    → { stack:, token:, tool:, handler:, known: }
#   :slash   → { stack:, token:, tool:, auth:, known: }
#   :hashtag → { stack:, handle:, action:, rest: }
#
# `known: false` means no grammar tool/spec matched — i.e. the input falls to the
# unknown/natural-language path. Greeting/farewell are NL-detected (no tool token),
# so they read as `known: false` here and are covered by their own handler specs.
module DispatchIntent
  module_function

  # Shape classifier — the single source of stack routing.
  def shape(input)
    s = input.to_s.strip
    return :slash   if s.start_with?("/")
    return :hashtag if s.start_with?("#")

    :chat
  end

  def parsed_intent(input)
    s = input.to_s.strip
    case shape(s)
    when :slash   then slash_intent(s)
    when :hashtag then hashtag_intent(s)
    else               chat_intent(s)
    end
  end

  def chat_intent(stripped)
    token     = stripped.split(/\s+/).first.to_s.downcase
    spec      = grammar_spec(:chat, token)
    canonical = spec&.name
    handler   = canonical && Pito::Chat::Registry.lookup(canonical)
    { stack: :chat, token: token, tool: canonical, handler: handler, known: !handler.nil? }
  end

  def slash_intent(stripped)
    token = stripped.delete_prefix("/").split(/\s+/).first.to_s.downcase
    spec  = grammar_spec(:slash, token)
    { stack: :slash, token: token, tool: spec&.name, auth: spec&.auth, known: !spec.nil? }
  end

  def hashtag_intent(stripped)
    m = stripped.match(/\A#(\S+)\s*(\S+)?\s*(.*)\z/m)
    {
      stack:  :hashtag,
      handle: m && m[1],
      action: (m && m[2])&.downcase,
      rest:   (m && m[3]).to_s.strip
    }
  end

  # Grammar spec for a token (alias-aware), or nil. Empty token → nil.
  def grammar_spec(namespace, token)
    return nil if token.blank?

    Pito::Grammar::Registry.specs_for_alias(namespace: namespace, token: token.to_sym)
  end
end

RSpec.configure do |config|
  config.include DispatchIntent
end
