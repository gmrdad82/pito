# frozen_string_literal: true

require "strscan"

module Pito
  module Event
    module Ai
      # A prose block inside an :ai message — escaped monospace text, newlines
      # preserved, dressed ONLY with the inline styling the content ontology
      # (config/pito/content.yml) declares: **bold**, *italic*, and
      # [cyan]…[/cyan]-style color spans from the allowed palette. Disallowed
      # color tags are unwrapped to plain text; stray markdown the model leaks
      # (backticks, #-headers, > quotes) is stripped — structure belongs in
      # typed blocks, never in markup. Kaomoji pass through as plain text.
      #
      # timestamp: (optional) renders the "HH:MM " prefix INLINE ahead of the
      # prose — the message's first line reads "05:22 Iată…" and wrapped lines
      # return to the left margin (no hanging indent under the prefix).
      class TextBlockComponent < ViewComponent::Base
        COLOR_CLASSES = {
          "cyan"  => "text-cyan",
          "red"   => "text-red",
          "green" => "text-green"
        }.freeze

        def initialize(text:, timestamp: nil)
          @text      = strip_markdown(text.to_s)
          @timestamp = timestamp
        end

        attr_reader :text

        def call
          tag.div(class: "whitespace-pre-wrap text-fg") do
            prefix = render(Pito::Event::TimestampPrefixComponent.new(timestamp: @timestamp)) if @timestamp
            safe_join([ prefix, styled(text) ].compact)
          end
        end

        private

        def strip_markdown(value)
          value
            .gsub(/`([^`\n]*)`/, '\1')
            .gsub(/^#+\s+/, "")
            .gsub(/^>\s?/, "")
        end

        # The declared inline notation → styled spans. Everything is built
        # from escaped nodes (plain strings escape via safe_join; span bodies
        # via tag.span) — the model's text NEVER reaches the page as markup.
        def styled(value)
          value   = unwrap_disallowed_colors(value)
          scanner = StringScanner.new(value)
          nodes   = []

          while (chunk = scanner.scan_until(inline_pattern))
            plain = chunk[0...-scanner.matched.length]
            nodes << plain unless plain.empty?
            nodes << styled_span(inline_pattern.match(scanner.matched))
          end
          nodes << scanner.rest unless scanner.rest.empty?

          safe_join(nodes)
        end

        def styled_span(m)
          if m[1]    then tag.span(m[1], class: "font-bold")
          elsif m[2] then tag.span(m[2], class: "italic")
          else            tag.span(m[4], class: COLOR_CLASSES[m[3]])
          end
        end

        # **bold**, *italic*, and the allowed [color]…[/color] tags.
        def inline_pattern
          @inline_pattern ||= begin
            colors = allowed_colors
            color_alt = colors.any? ? "|\\[(#{colors.join("|")})\\](.*?)\\[\\/\\3\\]" : ""
            /\*\*(.+?)\*\*|\*([^*\n]+)\*#{color_alt}/m
          end
        end

        # A color tag outside the allowed palette unwraps to its inner text.
        def unwrap_disallowed_colors(value)
          value.gsub(/\[([a-z]+)\](.*?)\[\/\1\]/m) do
            allowed_colors.include?(Regexp.last_match(1)) ? Regexp.last_match(0) : Regexp.last_match(2)
          end
        end

        # Renderable ∩ declared — a color the YAML allows but no class supports
        # never reaches the page (the registry also validates this at load).
        def allowed_colors
          @allowed_colors ||= ::Ai::ContentRegistry.allowed_colors & COLOR_CLASSES.keys
        end
      end
    end
  end
end
