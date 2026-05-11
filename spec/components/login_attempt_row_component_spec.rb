require "rails_helper"

RSpec.describe LoginAttemptRowComponent, type: :component do
  def wrap_in_table(component)
    # The component renders a `<tr>`; capybara queries against a wrapped
    # table so rows are valid HTML and `have_css` selectors work.
    render_inline(component)
  end

  context "success row" do
    let(:attempt) { create(:login_attempt, :success, :with_geo) }

    it "renders the result label 'success'" do
      wrap_in_table(described_class.new(attempt: attempt))
      expect(page).to have_text("success")
    end

    it "renders the reason copy" do
      wrap_in_table(described_class.new(attempt: attempt))
      expect(page).to have_text("trusted location")
    end

    it "renders the geo summary" do
      wrap_in_table(described_class.new(attempt: attempt))
      expect(page).to have_text(/Bucharest/)
    end

    it "renders the masked fingerprint (first 12 chars)" do
      wrap_in_table(described_class.new(attempt: attempt))
      expect(page).to have_text(attempt.fingerprint_hash[0, 12])
      expect(page).not_to have_text(attempt.fingerprint_hash)
    end

    it "renders a detail link by default" do
      wrap_in_table(described_class.new(attempt: attempt))
      expect(page).to have_link("[detail]", href: "/settings/security/attempts/#{attempt.id}")
    end

    it "hides the detail link when show_detail_link: false" do
      wrap_in_table(described_class.new(attempt: attempt, show_detail_link: false))
      expect(page).not_to have_link("[detail]")
    end
  end

  context "failed row" do
    let(:attempt) { create(:login_attempt) } # default factory = failed/wrong_password

    it "renders the failed result with muted text class" do
      wrap_in_table(described_class.new(attempt: attempt))
      expect(page).to have_css("td.text-muted", text: "failed")
    end

    it "renders the reason 'wrong password'" do
      wrap_in_table(described_class.new(attempt: attempt))
      expect(page).to have_text("wrong password")
    end
  end

  context "blocked row" do
    let(:attempt) { create(:login_attempt, :blocked) }

    it "renders the blocked result with text-danger class" do
      wrap_in_table(described_class.new(attempt: attempt))
      expect(page).to have_css("td.text-danger", text: "blocked")
    end
  end

  context "row missing geo" do
    let(:attempt) { create(:login_attempt) }

    it "renders 'location unknown' placeholder" do
      wrap_in_table(described_class.new(attempt: attempt))
      expect(page).to have_text("location unknown")
    end
  end
end
