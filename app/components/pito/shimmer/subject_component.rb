# frozen_string_literal: true

module Pito
  module Shimmer
    # Renders a message-intro SUBJECT — the %{title} / %{game} / %{name} value of
    # an intro line — with the pito-blue→purple shimmer (.pito-subject-shimmer)
    # and a shared staggered offset (Pito::Shimmer.offset_class) so adjacent
    # subjects are out of phase (never synchronised). The subject equivalent of
    # the cyan identifier TokenComponent; its colour is the INVERSE of the
    # hashtag shimmer (purple→blue).
    #
    #   render(Pito::Shimmer::SubjectComponent.new(text: video.title))
    #
    # String-only call sites (the HTML-aware copy renderer in Pito::Copy that
    # wraps a named placeholder) use the class methods so they never re-derive
    # the offset math by hand:
    #   Pito::Shimmer::SubjectComponent.css_class(title, seed: row_index)
    #   Pito::Shimmer::SubjectComponent.html(title)
    class SubjectComponent < ViewComponent::Base
      SHIMMER_CLASS = "pito-subject-shimmer"

      # Full class string for a subject-shimmer span (colour + shared offset +
      # extra). `seed:` is forwarded to Pito::Shimmer.offset_class so that
      # repeated subjects can break synchrony.
      def self.css_class(text, extra: nil, seed: nil)
        [ SHIMMER_CLASS, Pito::Shimmer.offset_class(text, seed: seed), extra ].compact.join(" ")
      end

      # html-safe <span> for builders / the copy renderer that compose raw markup.
      # `tag.span` escapes its content, so pass the RAW (un-escaped) value — the
      # subject text is escaped exactly once (see Pito::Copy.render_html).
      def self.html(text, extra: nil, seed: nil)
        ActionController::Base.helpers.tag.span(text, class: css_class(text, extra: extra, seed: seed))
      end

      def initialize(text:, extra_class: nil, seed: nil)
        @text        = text.to_s
        @extra_class = extra_class
        @seed        = seed
      end

      def call
        tag.span(@text, class: self.class.css_class(@text, extra: @extra_class, seed: @seed))
      end
    end
  end
end
