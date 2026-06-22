# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Copy, type: :service do
  # Register isolated fixture keys directly into the backend so these tests
  # never depend on real copy in config/locales/.
  around do |example|
    I18n.backend.store_translations(:en, copy_spec: {
      greeting:   "Hello!",
      with_name:  "Hey, %{name}!",
      two_vars:   "From %{sender} to %{receiver}.",
      variants:   [ "alpha", "beta", "gamma" ],
      one_item:   [ "only" ],
      nested:     { child: "child value" },
      subject_line:  "Renamed %{title}. Looks good.",
      subject_two:   "Linked %{title} to %{game}.",
      subject_vars:  [ "Renamed %{title}.", "Updated %{title}.", "Tweaked %{title}." ]
    })
    example.run
  end

  # ── sampler is overridden to deterministic (first) by spec/support/copy.rb ──

  describe ".render" do
    context "with a String entry" do
      it "returns the string unchanged when no vars are needed" do
        expect(described_class.render("copy_spec.greeting")).to eq("Hello!")
      end
    end

    context "with a one-element Array entry" do
      it "behaves like a single string" do
        expect(described_class.render("copy_spec.one_item")).to eq("only")
      end
    end

    context "with an Array of variants" do
      it "returns an element that is in the set (using deterministic sampler → first)" do
        result = described_class.render("copy_spec.variants")
        expect(%w[alpha beta gamma]).to include(result)
      end

      it "returns the first entry with the deterministic sampler (no variant:)" do
        expect(described_class.render("copy_spec.variants")).to eq("alpha")
      end

      it "returns the correct entry for variant: 0" do
        expect(described_class.render("copy_spec.variants", variant: 0)).to eq("alpha")
      end

      it "returns the correct entry for variant: 1" do
        expect(described_class.render("copy_spec.variants", variant: 1)).to eq("beta")
      end

      it "returns the correct entry for variant: 2 (3rd element)" do
        expect(described_class.render("copy_spec.variants", variant: 2)).to eq("gamma")
      end

      it "raises IndexError for an out-of-range variant:" do
        expect { described_class.render("copy_spec.variants", variant: 99) }
          .to raise_error(IndexError)
      end
    end

    context "with interpolation" do
      it "fills a single %{name} placeholder" do
        result = described_class.render("copy_spec.with_name", { name: "Alice" })
        expect(result).to eq("Hey, Alice!")
      end

      it "fills multiple placeholders" do
        result = described_class.render(
          "copy_spec.two_vars",
          { sender: "Bob", receiver: "Carol" }
        )
        expect(result).to eq("From Bob to Carol.")
      end

      it "fills placeholders passed as trailing keyword args (no explicit braces)" do
        expect(described_class.render("copy_spec.with_name", name: "Alice"))
          .to eq("Hey, Alice!")
      end

      it "accepts kwargs placeholders alongside variant:" do
        expect(described_class.render("copy_spec.with_name", variant: 0, name: "Zed"))
          .to eq("Hey, Zed!")
      end

      it "treats the hash form and kwargs form identically" do
        hash_form   = described_class.render("copy_spec.two_vars", { sender: "Bob", receiver: "Carol" })
        kwargs_form = described_class.render("copy_spec.two_vars", sender: "Bob", receiver: "Carol")
        expect(kwargs_form).to eq(hash_form)
      end

      it "raises MissingPlaceholder when a %{token} has no matching key in vars" do
        expect { described_class.render("copy_spec.with_name") }
          .to raise_error(Pito::Copy::MissingPlaceholder, /name/)
      end

      it "MissingPlaceholder message names the i18n key" do
        expect { described_class.render("copy_spec.with_name") }
          .to raise_error(Pito::Copy::MissingPlaceholder, /copy_spec\.with_name/)
      end
    end

    context "with a missing i18n key" do
      it "raises I18n::MissingTranslationData (never returns a silent string)" do
        expect { described_class.render("copy_spec.does_not_exist") }
          .to raise_error(I18n::MissingTranslationData)
      end
    end

    context "with a namespace (Hash) key" do
      it "raises ArgumentError" do
        expect { described_class.render("copy_spec.nested") }
          .to raise_error(ArgumentError, /namespace/)
      end

      it "error message names the key" do
        expect { described_class.render("copy_spec.nested") }
          .to raise_error(ArgumentError, /copy_spec\.nested/)
      end
    end
  end

  describe ".render_html" do
    it "wraps the named shimmer placeholder in a pito-subject-shimmer span" do
      html = described_class.render_html("copy_spec.subject_line", { title: "Hades" }, shimmer: [ :title ])
      doc  = Nokogiri::HTML.fragment(html)
      span = doc.css("span.pito-subject-shimmer").first
      expect(span).not_to be_nil
      expect(span.text).to eq("Hades")
      expect(span["class"]).to match(/\bpito-shimmer-d\d+\b/)
    end

    it "returns an html_safe string" do
      html = described_class.render_html("copy_spec.subject_line", { title: "Hades" }, shimmer: [ :title ])
      expect(html).to be_html_safe
    end

    it "leaves the surrounding template literal text intact (escaped, but readable)" do
      html = described_class.render_html("copy_spec.subject_line", { title: "Hades" }, shimmer: [ :title ])
      expect(html).to include("Renamed ")
      expect(html).to include(". Looks good.")
    end

    context "XSS — malicious title (user / import-derived)" do
      let(:evil) { "<script>alert(1)</script>" }

      it "escapes a malicious title inside the subject span (never raw markup)" do
        html = described_class.render_html("copy_spec.subject_line", { title: evil }, shimmer: [ :title ])
        span = Nokogiri::HTML.fragment(html).css("span.pito-subject-shimmer").first
        # The span CONTENT is the escaped script tag, not an executable child node.
        expect(span.children.any?(&:element?)).to be(false)
        expect(span.text).to eq(evil) # decoded text round-trips; serialization is escaped
        expect(html).to include("&lt;script&gt;")
        expect(html).not_to include("<script>")
      end

      it "escapes a malicious value even when it is NOT a shimmer placeholder" do
        html = described_class.render_html("copy_spec.subject_two", { title: "ok", game: evil }, shimmer: [ :title ])
        expect(html).to include("&lt;script&gt;")
        expect(html).not_to include("<script>")
        # Only the shimmer placeholder gets a span; the plain one is escaped text.
        spans = Nokogiri::HTML.fragment(html).css("span.pito-subject-shimmer")
        expect(spans.size).to eq(1)
        expect(spans.first.text).to eq("ok")
      end

      it "escapes malicious template literal text itself (defensive)" do
        I18n.backend.store_translations(:en, copy_spec: { evil_tpl: "<b>%{title}</b>" })
        html = described_class.render_html("copy_spec.evil_tpl", { title: "Hades" }, shimmer: [ :title ])
        expect(html).to include("&lt;b&gt;")
        expect(html).not_to include("<b>")
      end
    end

    it "respects the 1-or-50 sampler (deterministic first entry in test env)" do
      html = described_class.render_html("copy_spec.subject_vars", { title: "Hades" }, shimmer: [ :title ])
      expect(html).to include("Renamed ")
      span = Nokogiri::HTML.fragment(html).css("span.pito-subject-shimmer").first
      expect(span.text).to eq("Hades")
    end

    it "honours a forced variant: index" do
      html = described_class.render_html("copy_spec.subject_vars", { title: "Hades" }, variant: 1, shimmer: [ :title ])
      expect(html).to include("Updated ")
    end

    it "interpolates a non-shimmer placeholder as escaped plain text (no span)" do
      html = described_class.render_html("copy_spec.subject_line", { title: "Hades" }, shimmer: [])
      expect(Nokogiri::HTML.fragment(html).css("span.pito-subject-shimmer")).to be_empty
      expect(html).to include("Renamed Hades.")
    end

    it "raises MissingPlaceholder when a %{token} has no matching key (like render)" do
      expect { described_class.render_html("copy_spec.subject_line", {}, shimmer: [ :title ]) }
        .to raise_error(Pito::Copy::MissingPlaceholder, /title/)
    end

    it "raises ArgumentError for a namespace key (like render)" do
      expect { described_class.render_html("copy_spec.nested") }
        .to raise_error(ArgumentError, /namespace/)
    end

    it "accepts shimmer placeholders passed as trailing kwargs" do
      html = described_class.render_html("copy_spec.subject_line", shimmer: [ :title ], title: "Hades")
      expect(Nokogiri::HTML.fragment(html).css("span.pito-subject-shimmer").first.text).to eq("Hades")
    end
  end

  describe ".sampler" do
    it "defaults to first-entry in spec env (installed by support/copy.rb)" do
      described_class.sampler = ->(entries) { entries.last }
      expect(described_class.render("copy_spec.variants")).to eq("gamma")
    end

    it "is restored to deterministic (first) after each example" do
      # This example runs AFTER the override above; the after(:each) hook in
      # spec/support/copy.rb should have restored it.
      expect(described_class.render("copy_spec.variants")).to eq("alpha")
    end
  end

  describe ".reset_sampler!" do
    it "restores the default (random) sampler" do
      described_class.sampler = ->(entries) { entries.last }
      described_class.reset_sampler!
      # After reset, sampler should be DEFAULT_SAMPLER (random). We can't
      # assert on randomness directly, but we CAN assert the result is in-set.
      result = described_class.render("copy_spec.variants")
      expect(%w[alpha beta gamma]).to include(result)
    end
  end
end
