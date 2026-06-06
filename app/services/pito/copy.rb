# frozen_string_literal: true

module Pito
  # Copy engine — the single seam every caller uses for user-facing strings.
  #
  # == Contract
  #
  # Pito::Copy.render(key, vars = {}, variant: nil) → String
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
    # @param key     [Symbol, String] I18n key
    # @param vars    [Hash]           placeholder values (symbol keys)
    # @param variant [Integer, nil]   forced variant index; nil = sampler
    # @return        [String]
    def render(key, vars = {}, variant: nil)
      # 1. Resolve — do NOT pass vars to I18n; we interpolate ourselves so that
      #    array entries work (I18n only interpolates string leaves).
      raw = I18n.t(key, raise: true)

      # 2. Reject namespace keys (Hash means the key points to a subtree).
      if raw.is_a?(Hash)
        raise ArgumentError,
              "copy key `#{key}` points to a namespace, not a line/list"
      end

      # 3. Normalise to Array (a String becomes a 1-element array).
      entries = Array(raw)

      # 4. Pick the entry.
      chosen =
        if variant.nil?
          sampler.call(entries)
        else
          entries.fetch(variant) # raises IndexError if out of range
        end

      # 5. Interpolate %{name} tokens.
      interpolate(key, chosen.to_s, vars)
    end

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
  end
end
