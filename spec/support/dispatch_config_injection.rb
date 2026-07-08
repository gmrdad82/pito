# frozen_string_literal: true

# Test-support seam for injecting a synthetic verbs.yml document into
# Pito::Dispatch::Config for the duration of an example — the config-document
# injection helper the add-a-verb proof (spec/dispatch/add_a_verb_proof_spec.rb)
# relies on. It is the ONLY new test-support code that proof needs.
#
# WHY A DOC OVERRIDE (and not a Config::PATH + stub_const seam)
#   Pito::Dispatch::Config memoizes the parsed, deep-frozen document in the module
#   ivar @data (see lib/pito/dispatch/config.rb). Overriding @data is the
#   least-invasive, deterministic seam:
#
#     * it hands the EXACT shape the real loader produces (symbol-keyed, deep
#       frozen) to every downstream reader — Router, Matrix, Grammar::ConfigSource,
#       Schema, ReplyBinding — with ZERO changes to any of them;
#     * restore is a plain Config.reload! (nils @data → the next read re-parses the
#       real file). This does NOT depend on rspec-mocks teardown ordering: a
#       stub_const on Config::PATH reverts during mocks teardown, which runs AFTER
#       the example's own `after` hooks, so a reload! inside an `after` would
#       re-read the STILL-stubbed temp file and leak the fixture into later specs.
#       The doc override sidesteps that failure mode entirely.
#
#   The synthetic verb still originates as YAML text: callers pass YAML fragments
#   parsed with the SAME `YAML.safe_load(symbolize_names: true)` call the real
#   loader uses, merged over a frozen-safe deep copy of the live document.
#
# LEAK-PROOFING (survives random --seed ordering)
#   inject_dispatch_config! rebuilds every cache derived from Config.data — the
#   reply Matrix and the Grammar Registry — from the injected document;
#   restore_dispatch_config! rebuilds them from the real file. rails_helper's
#   global before(:each) re-runs Grammar::Registry.register_all! as well, a second
#   safety net once Config is restored.
module DispatchConfigInjection
  # Merge the given YAML fragments into the live config document, install it, and
  # rebuild the derived caches. Returns the injected (deep-frozen) document.
  def inject_dispatch_config!(verbs: nil, vocabularies: nil, universal_reply: nil, mcp_readers: nil)
    doc = Pito::Dispatch::Config.data.deep_dup # ActiveSupport deep_dup → unfrozen tree
    merge_section!(doc, :verbs, verbs)
    merge_section!(doc, :vocabularies, vocabularies)
    merge_section!(doc, :universal_reply, universal_reply)
    merge_section!(doc, :mcp_readers, mcp_readers)

    @injected_dispatch_document = deep_freeze(doc)
    Pito::Dispatch::Config.instance_variable_set(:@data, @injected_dispatch_document)
    rebuild_dispatch_caches!
    @injected_dispatch_document
  end

  # The document installed by the most recent inject_dispatch_config! call.
  attr_reader :injected_dispatch_document

  # Restore the real verbs.yml document + every derived cache. Idempotent.
  def restore_dispatch_config!
    Pito::Dispatch::Config.reload!
    rebuild_dispatch_caches!
    @injected_dispatch_document = nil
  end

  private

  def merge_section!(doc, section, yaml)
    return if yaml.nil?

    fragment = YAML.safe_load(yaml, symbolize_names: true) || {}
    (doc[section] ||= {}).merge!(fragment)
  end

  def rebuild_dispatch_caches!
    Pito::Dispatch::Matrix.reload!
    Pito::Grammar::Registry.register_all!
  end

  # Mirrors Pito::Dispatch::Config#deep_freeze (private) so the injected document
  # matches the frozen shape the real loader hands downstream code.
  def deep_freeze(obj)
    case obj
    when Hash  then obj.transform_values { |v| deep_freeze(v) }.freeze
    when Array then obj.map { |v| deep_freeze(v) }.freeze
    else            obj.frozen? ? obj : obj.freeze
    end
  end
end

RSpec.configure do |config|
  config.include DispatchConfigInjection, type: :dispatch
end
