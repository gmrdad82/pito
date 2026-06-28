# frozen_string_literal: true

module Pito
  # Copy engine — the single seam every caller uses for user-facing strings.
  #
  # == Contract
  #
  # Pito::Copy.render(key, vars = {}, variant: nil, **kwargs) → String
  #
  # Placeholder values may be passed as an explicit Hash (+vars+) or as trailing
  # keyword arguments — both are equivalent.
  #
  # * +key+     — an I18n key (Symbol or String).  The key MUST resolve to a
  #               String (one line) or an Array of Strings (variants).  If it
  #               resolves to a Hash (i.e. a namespace, not a leaf), ArgumentError
  #               is raised.  If the key is missing entirely, I18n raises
  #               I18n::MissingTranslationData — that exception is NOT rescued
  #               (callers must keep their keys valid; silent "" would hide bugs).
  #
  # * +vars+    — a Hash (symbol keys) of placeholder values.  Every +%{name}+
  #               token in the chosen string is replaced with vars[:name].  If a
  #               token has no matching key, Pito::Copy::MissingPlaceholder is
  #               raised (the error message names both the i18n key and the
  #               missing placeholder).
  #
  # * +variant:+ — optional Integer.  When given, +entries.fetch(variant)+ is
  #               called, which surfaces IndexError for out-of-range indices.
  #               When omitted, the engine delegates to +Pito::Copy.sampler+
  #               (default: random).
  #
  # == Sampler
  #
  # Pito::Copy.sampler is a module-level Proc that receives the entries Array
  # and returns one element.  The default implementation calls Array#sample
  # (random).  Specs override it to be deterministic (first element) via the
  # support hook in spec/support/copy.rb.  Individual examples may also assign
  # a custom sampler (it is restored after each example by the support hook).
  #
  # == Usage
  #
  #   Pito::Copy.render("pito.copy.theme.applied")
  #   # => "Theme applied. Enjoy."
  #
  #   Pito::Copy.render("pito.copy.greet", { name: "Alice" })
  #   # => "Hey, Alice!"
  #
  #   Pito::Copy.render("pito.copy.thinking.verbs", variant: 2)
  #   # => the 3rd element (index 2) of the array
  #
  module Copy
    # Raised when a +%{placeholder}+ token has no matching key in +vars+.
    class MissingPlaceholder < KeyError
      def initialize(i18n_key, placeholder_name)
        super("copy key `#{i18n_key}` references placeholder `%{#{placeholder_name}}` " \
              "but no matching key was supplied in vars")
      end
    end

    DEFAULT_SAMPLER = ->(entries) { entries.sample }
    private_constant :DEFAULT_SAMPLER

    module_function

    # Returns the current sampler proc.
    def sampler
      @sampler || DEFAULT_SAMPLER
    end

    # Sets a custom sampler proc.  Assign +nil+ (or call +reset_sampler!+) to
    # restore the default random behaviour.
    def sampler=(proc)
      @sampler = proc
    end

    # Restores the sampler to the default (random).
    def reset_sampler!
      @sampler = nil
    end

    # Renders the copy string for +key+.
    #
    # Placeholder values may be passed either as an explicit Hash or as trailing
    # keyword arguments — both work:
    #
    #   Pito::Copy.render("pito.copy.greet", name: "Alice")   # kwargs form
    #   Pito::Copy.render("pito.copy.greet", { name: "Alice" }) # hash form
    #
    # +variant+ is a reserved keyword (the forced index). To use a placeholder
    # literally named +variant+, pass it via the explicit Hash form.
    #
    # @param key     [Symbol, String] I18n key
    # @param vars    [Hash]           placeholder values (symbol keys)
    # @param variant [Integer, nil]   forced variant index; nil = sampler
    # @param extra   [Hash]           placeholder values given as keyword args
    # @return        [String]
    def render(key, vars = {}, variant: nil, **extra)
      # 0. Merge keyword-form placeholders into vars, so `render(key, a: 1)` and
      #    `render(key, { a: 1 })` are equivalent (no explicit-braces footgun).
      vars = vars.merge(extra) unless extra.empty?

      # 1-4. Resolve the key + pick the variant (sampler or forced index).
      chosen = resolve(key, variant)

      # 5. Interpolate %{name} tokens.
      interpolate(key, chosen, vars)
    end

    # HTML-aware sibling of +render+ for the scrollback: same key resolution and
    # 1-or-50 variant sampling, but it produces an +html_safe+ String in which
    # the SUBJECT placeholder(s) named in +shimmer:+ are wrapped in a
    # +Pito::Shimmer::SubjectComponent+ span (the pito-blue→purple intro shimmer).
    #
    # == XSS contract (titles are user / import-derived → untrusted)
    #
    # Everything is escaped before it reaches the output:
    #   * the template literal text is +html_escape+-d first, so any markup that
    #     ever lands in a copy string is inert;
    #   * each interpolated value is escaped too — shimmer values via the span's
    #     own content-escaping (+tag.span+), plain values via +html_escape+.
    # Only this method's own <span> wrappers are trusted markup; the final
    # +html_safe+ string therefore contains no un-escaped caller data.
    #
    #   Pito::Copy.render_html("pito.copy.video.renamed", { title: t }, shimmer: [ :title ])
    #
    # @param key     [Symbol, String]   I18n key (resolved exactly like +render+)
    # @param vars    [Hash]             placeholder values (symbol keys)
    # @param shimmer [Array<Symbol>]    placeholder names to wrap in a subject span
    # @param variant [Integer, nil]     forced variant index; nil = sampler
    # @param extra   [Hash]             placeholder values given as keyword args
    # @return        [ActiveSupport::SafeBuffer]
    def render_html(key, vars = {}, shimmer: [], reference: [], variant: nil, **extra)
      vars = vars.merge(extra) unless extra.empty?
      shimmer_names   = Array(shimmer).map(&:to_sym)
      reference_names = Array(reference).map(&:to_sym)

      chosen = resolve(key, variant)
      interpolate_html(key, chosen, vars, shimmer_names, reference_names)
    end

    # Resolves +key+ to one chosen entry (String) applying the same namespace
    # guard + 1-or-50 sampler/forced-index logic as the public renderers.
    def resolve(key, variant)
      # Resolve — do NOT pass vars to I18n; we interpolate ourselves so that
      # array entries work (I18n only interpolates string leaves).
      raw = I18n.t(key, raise: true)

      # Reject namespace keys (Hash means the key points to a subtree).
      if raw.is_a?(Hash)
        raise ArgumentError,
              "copy key `#{key}` points to a namespace, not a line/list"
      end

      # Normalise to Array (a String becomes a 1-element array), then pick.
      entries = Array(raw)
      chosen =
        if variant.nil?
          sampler.call(entries)
        else
          entries.fetch(variant) # raises IndexError if out of range
        end
      chosen.to_s
    end
    private_class_method :resolve

    # Performs %{name} placeholder substitution.
    # Private — exposed only for testability; callers must use +render+.
    def interpolate(key, string, vars)
      string.gsub(/%\{([a-zA-Z_]\w*)\}/) do
        name = ::Regexp.last_match(1)
        vars.fetch(name.to_sym) do
          raise MissingPlaceholder.new(key, name)
        end
      end
    end
    private_class_method :interpolate

    # HTML-safe %{name} substitution. The literal template text is escaped up
    # front; each placeholder is then replaced with either a subject-shimmer
    # span (names in +shimmer_names+) or an html-escaped plain value. Operates on
    # a plain String (escaped template), html_safe only at the very end, so the
    # span markup is never re-escaped and the values are never double-escaped.
    def interpolate_html(key, string, vars, shimmer_names, reference_names = [])
      template = ERB::Util.html_escape(string).to_str
      template.gsub(/%\{([a-zA-Z_]\w*)\}/) do
        name  = ::Regexp.last_match(1).to_sym
        value = vars.fetch(name) { raise MissingPlaceholder.new(key, name) }
        if shimmer_names.include?(name)
          # tag.span (inside SubjectComponent.html) escapes the content itself.
          Pito::Shimmer::SubjectComponent.html(value.to_s).to_str
        elsif reference_names.include?(name)
          # The cyan→pito-blue identifier token — a secondary "reference" to the
          # purple→blue subject (e.g. the period alongside the entity subject).
          Pito::Shimmer::TokenComponent.html(value.to_s).to_str
        else
          ERB::Util.html_escape(value.to_s).to_str
        end
      end.html_safe
    end
    private_class_method :interpolate_html
  end
end
