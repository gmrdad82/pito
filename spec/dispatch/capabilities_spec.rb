# frozen_string_literal: true

require "rails_helper"

# v1.6 unified grammar — the ORPHAN + COPY guard. The verbs.yml `capabilities:` block
# is the single source of truth for the column/filter vocabulary that --help, MCP,
# and autocomplete read. This suite proves config ↔ Ruby (the behavior procs) stay in
# 1:1 sync and that every declared element has a resolvable description — so a column
# can never exist in one place but not the other, and none ships undocumented.
RSpec.describe "verbs.yml capabilities — orphan + copy guard", type: :dispatch do
  Cap = Pito::Grammar::Capability

  RUBY = {
    "games"    => Pito::MessageBuilder::Game::ListColumns,
    "vids"     => Pito::MessageBuilder::Video::ListColumns,
    "channels" => Pito::MessageBuilder::Channel::ListColumns
  }.freeze

  RUBY.each do |noun, ruby|
    describe "list · #{noun} columns (config ↔ Ruby)" do
      subject(:cols) { Cap.columns(:list, noun) }

      it "config columns are EXACTLY the Ruby COLUMNS (no orphan either way)" do
        expect(cols.map(&:name)).to match_array(ruby::COLUMNS.keys.map(&:to_s))
      end

      it "config tokens (name + aliases) match Ruby aliases per column" do
        cols.each do |c|
          expect(c.tokens.sort).to eq(ruby::COLUMNS.fetch(c.name.to_sym)[:aliases].map(&:to_s).sort),
                                   "token mismatch for #{noun}/#{c.name}"
        end
      end

      it "config `internal` matches Ruby" do
        cols.each do |c|
          expect(c.internal).to eq(ruby::COLUMNS.fetch(c.name.to_sym)[:internal] == true),
                                "internal mismatch for #{noun}/#{c.name}"
        end
      end

      it "every column has a resolvable, non-blank description (copy guard)" do
        cols.each { |c| expect(Pito::Copy.render(c.desc.to_s)).to be_present, "no copy for #{noun}/#{c.name}" }
      end
    end
  end

  # SORT_VOCAB-backed nouns (game/video): sortable + requires_with cross-check.
  { "games" => Pito::MessageBuilder::Game::ListColumns, "vids" => Pito::MessageBuilder::Video::ListColumns }.each do |noun, ruby|
    describe "list · #{noun} sort semantics" do
      it "config `sortable` matches Ruby SORT_VOCAB coverage" do
        Cap.columns(:list, noun).each do |c|
          expect(c.sortable).to eq(ruby::SORT_VOCAB.value?(c.name.to_sym)), "sortable mismatch for #{noun}/#{c.name}"
        end
      end

      # ALL columns, not just config-sortable ones: a column that is sortable in
      # config but wrongly missing its SORT_SPECS entry (or vice versa) must still
      # surface here. A genuinely non-sortable column (games/platform; vids/category,
      # scheduled) has NO SORT_SPECS entry at all — Ruby never encodes a with-requirement
      # for a column it never sorts by — so `if spec` leaves those unchecked; that is a
      # real gap this suite cannot close without inventing Ruby structure that isn't there.
      it "config `requires_with` matches Ruby SORT_SPECS coverage" do
        Cap.columns(:list, noun).each do |c|
          spec = ruby::SORT_SPECS[c.name.to_sym]
          expect(c.requires_with).to eq(spec[:requires_with]), "requires_with mismatch for #{noun}/#{c.name}" if spec
        end
      end
    end
  end

  # Channels has no SORT_VOCAB/SORT_SPECS — sortability + the with-requirement are
  # expressed by sortable_tokens/sort_key_for instead (see Channel::ListColumns), so this
  # noun needs its own cross-check rather than joining the SORT_VOCAB-backed loop above.
  describe "list · channels sort semantics" do
    it "config `sortable` matches Ruby sortable_tokens coverage (every column visible)" do
      sortable = Pito::MessageBuilder::Channel::ListColumns.sortable_tokens(
        selected_columns: Pito::MessageBuilder::Channel::ListColumns::COLUMNS.keys
      )
      Cap.columns(:list, "channels").each do |c|
        expect(c.sortable).to eq(sortable.include?(c.name)), "sortable mismatch for channels/#{c.name}"
      end
    end

    it "config `requires_with` matches Ruby sort_key_for (a counter column sorts only while selected)" do
      Cap.columns(:list, "channels").each do |c|
        resolves_unselected = Pito::MessageBuilder::Channel::ListColumns.sort_key_for(c.name, selected_columns: []).present?
        resolves_selected   = Pito::MessageBuilder::Channel::ListColumns.sort_key_for(c.name, selected_columns: [ c.name.to_sym ]).present?
        expect(c.requires_with).to eq(!resolves_unselected && resolves_selected), "requires_with mismatch for channels/#{c.name}"
      end
    end
  end

  describe "list · channels defaults" do
    it "config `default: true` columns == Ruby DEFAULT_COLUMNS" do
      defaults = Cap.columns(:list, "channels").select(&:default).map(&:name)
      expect(defaults).to match_array(Pito::MessageBuilder::Channel::ListColumns::DEFAULT_COLUMNS.map(&:to_s))
    end
  end

  { "games" => %w[upcoming genre platform], "vids" => %w[published unlisted scheduled] }.each do |noun, expected|
    describe "list · #{noun} filters" do
      subject(:filters) { Cap.filters(:list, noun) }

      it "covers the filter surface" do
        expect(filters.map(&:name)).to match_array(expected)
      end

      it "every filter has a resolvable description" do
        filters.each { |f| expect(Pito::Copy.render(f.desc.to_s)).to be_present }
      end

      it "vocabulary-backed filters reference real vocabularies" do
        vocabs = Pito::Dispatch::Config.data[:vocabularies].keys.map(&:to_s)
        filters.filter_map(&:vocabulary).each { |v| expect(vocabs).to include(v) }
      end
    end
  end

  # GameListFilter derives its token maps from the :genres/:platforms config
  # vocabularies, mapping each canonical MEMBER through a Ruby member→substring
  # behavior table (`derive_tokens` silently skips a member with no behavior —
  # this guard is what makes that skip impossible to ship). Both directions:
  # a config member without Ruby behavior, or Ruby behavior for a member that
  # left config, is drift.
  describe "list · games filter vocabularies ↔ Ruby match behavior" do
    { genres:    Pito::Chat::GameListFilter::MEMBER_GENRE_SUBSTRINGS,
      platforms: Pito::Chat::GameListFilter::MEMBER_PLATFORM_SUBSTRINGS }.each do |vocab_name, behavior|
      it "every :#{vocab_name} member has exactly one Ruby substring mapping and vice versa" do
        members = Pito::Grammar::Registry.vocabulary(vocab_name).canonical
        expect(behavior.keys).to match_array(members)
      end

      it "every :#{vocab_name} token (member or synonym) derives a usable filter entry" do
        vocab  = Pito::Grammar::Registry.vocabulary(vocab_name)
        map    = vocab_name == :genres ? Pito::Chat::GameListFilter::GENRE_ALIASES
                                       : Pito::Chat::GameListFilter::PLATFORM_SYNONYMS
        tokens = vocab.canonical.map(&:downcase) + vocab.synonyms.keys.map(&:to_s)
        tokens.uniq.each do |token|
          expect(map).to have_key(token), "config token #{vocab_name}/#{token} derives no filter entry"
        end
      end
    end
  end
end
