# frozen_string_literal: true

module Pito
  module Chat
    Message = Data.define(:tool, :body_tokens, :kind, :raw) do
      # tool        — Symbol (:list, :show, :find) or nil for unknown
      # body_tokens — Array of Pito::Lex::Token (the remainder after the tool)
      # kind        — Symbol :new_turn or :unknown
      # raw         — String, the original input
    end
  end
end
