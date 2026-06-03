# frozen_string_literal: true

module Pito
  module Hashtag
    Message = Data.define(:handle, :body_tokens, :raw) do
      # handle      — Symbol, the word part of the handle (e.g. :reply for #reply-1234)
      # body_tokens — Array of Pito::Lex::Token (the remainder after the handle)
      # raw         — String, the original input
    end
  end
end
