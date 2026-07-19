# frozen_string_literal: true

require "rails_helper"

# Guard (owner, 2026-07-06): no copy sentence starts with a lowercase letter.
# Two mechanical checks over the REAL locale file:
#
#   1. No variant's raw text starts with a lowercase letter — except the
#      allowlisted chrome/fragment/syntax keys below, which are NOT sentences.
#   2. No variant leads with an interpolation whose value is KNOWN to render
#      lowercase (%{reference} "lifetime", %{metric} nouns, %{horizon} phrases,
#      %{theme} tokens, %{noun}/%{addable}/%{keys} column tokens, %{verb}
#      participles; %{subject} only under sync.intro, where it takes lowercase
#      scope labels). Echoes of user input (%{ref}, %{tokens}, %{target}) and
#      title/number/handle tokens are exempt — their case isn't copy's.
RSpec.describe "Pito::Copy capitalization guard", type: :service do
  # Literal command syntax, chrome tokens, and mid-line fragments — not sentences.
  ALLOWLISTED_LEAVES = %w[
    usage opt_with opt_sorted opt_without opt_sort
    delete_button sync_cta singular na start_chatting jump_to_end
    glyphs count suggestion_accept_hint
  ].freeze

  # Interpolations whose values always render lowercase at sentence start.
  LOWERCASE_TOKEN_LEAD = /\A%\{(reference|metric|horizon|theme|noun|addable|keys|verb)\}/

  def copy_strings
    tree = YAML.safe_load_file(Rails.root.join("config/locales/pito/copy/en.yml"))
    flatten(tree.dig("en", "pito", "copy"), %w[pito copy])
  end

  def flatten(node, path)
    case node
    when Hash  then node.flat_map { |k, v| flatten(v, path + [ k.to_s ]) }
    when Array then node.map { |v| [ path, v ] }
    else [ [ path, node.to_s ] ]
    end
  end

  it "no copy sentence starts with a lowercase letter" do
    offenders = copy_strings.reject { |path, _| ALLOWLISTED_LEAVES.include?(path.last) }
                            .select { |_, s| s.match?(/\A[a-z]/) }
    report = offenders.map { |path, s| "  #{path.join('.')}: #{s[0, 60]}" }.join("\n")
    expect(offenders).to be_empty, "Copy sentences must start capitalized:\n#{report}"
  end

  it "no copy sentence leads with a lowercase-rendering interpolation" do
    offenders = copy_strings.select do |path, s|
      s.match?(LOWERCASE_TOKEN_LEAD) ||
        (s.start_with?("%{subject}") && path.join(".").include?("sync.intro"))
    end
    report = offenders.map { |path, s| "  #{path.join('.')}: #{s[0, 60]}" }.join("\n")
    expect(offenders).to be_empty,
      "These lead with an interpolation that renders lowercase — reword so the " \
      "sentence opens capitalized:\n#{report}"
  end
end
