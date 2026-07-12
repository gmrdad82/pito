# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Grammar::HandlerDsl do
  before { Pito::Grammar::Registry.reset! }
  after  { Pito::Grammar::Registry.reset! }

  # ---------------------------------------------------------------------------
  # Slash handler with a full grammar block
  # ---------------------------------------------------------------------------
  describe "slash handler with grammar block" do
    let(:handler_class) do
      Class.new(Pito::Slash::Handler) do
        self.tool            = :demo
        self.description_key = "x"

        grammar do
          enum :status, source: :release_status, optional: true
          aliases :demoer
          auth :authenticated_only
        end
      end
    end

    subject(:spec) { handler_class.grammar_spec }

    it "returns a Pito::Grammar::Spec" do
      expect(spec).to be_a(Pito::Grammar::Spec)
    end

    it "has namespace :slash" do
      expect(spec.namespace).to eq(:slash)
    end

    it "has name :demo" do
      expect(spec.name).to eq(:demo)
    end

    it "has one slot named :status with kind :enum" do
      expect(spec.slots.size).to eq(1)
      slot = spec.slots.first
      expect(slot.name).to eq(:status)
      expect(slot.kind).to eq(:enum)
      expect(slot.optional).to be(true)
    end

    it "includes :demoer in aliases" do
      expect(spec.aliases).to include(:demoer)
    end

    it "has auth :authenticated_only" do
      expect(spec.auth).to eq(:authenticated_only)
    end
  end

  # ---------------------------------------------------------------------------
  # Slash handler with verb + description_key but NO grammar block → bare spec
  # ---------------------------------------------------------------------------
  describe "slash handler with verb+description_key but no grammar block" do
    let(:handler_class) do
      Class.new(Pito::Slash::Handler) do
        self.tool            = :bare
        self.description_key = "some.key"
      end
    end

    subject(:spec) { handler_class.grammar_spec }

    it "returns a Pito::Grammar::Spec" do
      expect(spec).to be_a(Pito::Grammar::Spec)
    end

    it "has namespace :slash" do
      expect(spec.namespace).to eq(:slash)
    end

    it "has name equal to verb" do
      expect(spec.name).to eq(:bare)
    end

    it "has an empty slots array" do
      expect(spec.slots).to eq([])
    end

    it "has default auth :any" do
      expect(spec.auth).to eq(:any)
    end
  end

  # ---------------------------------------------------------------------------
  # Hashtag handler with NO grammar block → nil
  # ---------------------------------------------------------------------------
  describe "hashtag handler with no grammar block" do
    let(:handler_class) do
      Class.new(Pito::Hashtag::Handler) do
        self.handle = :reply
      end
    end

    it "returns nil" do
      expect(handler_class.grammar_spec).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Chat handler with NO grammar block → nil
  # ---------------------------------------------------------------------------
  describe "chat handler with no grammar block" do
    let(:handler_class) do
      Class.new(Pito::Chat::Handler) do
        self.tool            = :search
        self.description_key = "chat.search.key"
      end
    end

    it "returns nil" do
      expect(handler_class.grammar_spec).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # DSL ivar isolation: subclasses start clean
  # ---------------------------------------------------------------------------
  describe "subclass ivar isolation via inherited" do
    it "does not inherit the parent grammar block" do
      parent = Class.new(Pito::Slash::Handler) do
        self.tool            = :parent
        self.description_key = "parent.key"
        grammar do
          free :query
        end
      end

      child = Class.new(parent) do
        self.tool            = :child
        self.description_key = "child.key"
      end

      # Parent has grammar declared; child does NOT inherit parent's grammar ivars.
      parent_spec = parent.grammar_spec
      child_spec  = child.grammar_spec

      expect(parent_spec.slots.size).to eq(1)
      expect(child_spec.slots).to eq([])
    end
  end

  # ---------------------------------------------------------------------------
  # Non-clobber: central spec registered first must win
  # ---------------------------------------------------------------------------
  describe "non-clobber in register_handler_specs" do
    # Strategy: We test the non-clobber rule directly via register_spec twice.
    # Calling register_handler_specs with real Handlers constants requires
    # defining classes under Pito::Slash::Handlers, which is awkward in specs.
    # Instead we exercise the skip logic by simulating what register_handler_specs
    # does: register a rich central spec first, then attempt to register a bare
    # handler spec for the same [namespace, name] — the second must be rejected.

    let(:central_slot) do
      Pito::Grammar::Slot.new(name: :genre, kind: :enum, source: :genres)
    end

    let(:central_spec) do
      Pito::Grammar::Spec.new(
        namespace: :slash,
        name:      :demo,
        slots:     [ central_slot ],
        auth:      :authenticated_only
      )
    end

    let(:bare_spec) do
      Pito::Grammar::Spec.new(
        namespace: :slash,
        name:      :demo,
        slots:     []
      )
    end

    it "does not overwrite a pre-registered central spec with a handler bare spec" do
      # Simulate Specs.register_all! registering the central spec first.
      Pito::Grammar::Registry.register_spec(central_spec)

      # Simulate what register_handler_specs would do for a bare handler:
      # it skips if a spec for [namespace, name] already exists.
      existing = Pito::Grammar::Registry.spec(namespace: :slash, name: :demo)
      Pito::Grammar::Registry.register_spec(bare_spec) if existing.nil?

      # The central spec (with one slot) must still be present.
      stored = Pito::Grammar::Registry.spec(namespace: :slash, name: :demo)
      expect(stored.slots.size).to eq(1)
      expect(stored.slots.first.name).to eq(:genre)
      expect(stored.auth).to eq(:authenticated_only)
    end

    it "registers a handler spec when no central spec is pre-registered" do
      # No central spec registered → handler spec is stored.
      Pito::Grammar::Registry.register_spec(bare_spec)
      stored = Pito::Grammar::Registry.spec(namespace: :slash, name: :demo)
      expect(stored).to eq(bare_spec)
    end

    context "with a stub Handlers constant for full register_handler_specs coverage" do
      let(:handler_class) do
        Class.new(Pito::Slash::Handler) do
          self.tool            = :demo
          self.description_key = "demo.key"
          # No grammar block → bare spec
        end
      end

      it "skips the handler spec when the central spec is already registered" do
        # Register the central rich spec first (mimics Specs.register_all!).
        Pito::Grammar::Registry.register_spec(central_spec)

        # Stub Handlers so register_handler_specs finds our handler class.
        stub_const("Pito::Slash::Handlers", Module.new)
        stub_const("Pito::Slash::Handlers::Demo", handler_class)

        Pito::Grammar::Registry.send(:register_handler_specs)

        stored = Pito::Grammar::Registry.spec(namespace: :slash, name: :demo)
        expect(stored.slots.size).to eq(1), "central spec's slot count must be preserved"
        expect(stored.auth).to eq(:authenticated_only)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Misc slot builder methods
  # ---------------------------------------------------------------------------
  describe "grammar builder methods" do
    it "builds literal, kv, free, connective slots" do
      klass = Class.new(Pito::Slash::Handler) do
        self.tool            = :test_all
        self.description_key = "test.all"

        grammar do
          literal    :platform, source: [ :pc, :ps5 ], synonyms: [ "playstation 5" ]
          kv         :page,     source: :dynamic
          free       :query,    optional: true
          connective :and
        end
      end

      spec = klass.grammar_spec
      expect(spec.slots.map(&:kind)).to eq(%i[literal kv free connective])
      expect(spec.slots.find { |s| s.name == :platform }.synonyms).to eq([ "playstation 5" ])
    end
  end
end
