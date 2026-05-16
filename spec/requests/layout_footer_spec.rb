require "rails_helper"

# Footer pito logo external link (2026-05-16). The small `Pito.png`
# image rendered next to the `&copy; YYYY — all rights reserved.`
# prose at the bottom-left of the footer is wrapped in an `<a>` that
# points to the marketing site at `https://pitomd.com`. Because the
# target is an external origin, the anchor MUST carry both the
# `target="_blank"` and the `rel="noopener noreferrer"` attributes —
# the canonical pairing per `docs/design.md`'s "External links —
# new tab convention" rule (also auto-applied by
# `BracketedLinkComponent` for absolute http(s) hrefs).
RSpec.describe "Layout footer pito logo", type: :request do
  def footer_html
    body = response.body
    match = body.match(%r{<footer\b.*?</footer>}m)
    expect(match).not_to be_nil, "expected to find <footer>...</footer> in the response"
    match[0]
  end

  describe "GET /" do
    before { get "/" }

    it "returns 200" do
      expect(response).to have_http_status(:ok)
    end

    it "wraps the pito logo in an external link to https://pitomd.com with target=_blank and rel=noopener noreferrer" do
      footer = footer_html
      logo_anchor = footer.match(%r{<a\b[^>]*href="https://pitomd\.com"[^>]*>\s*<img[^>]*src="/Pito\.png"[^>]*>\s*</a>}m)

      expect(logo_anchor).not_to be_nil,
        "expected the footer Pito.png logo to be wrapped in an <a> targeting https://pitomd.com"

      anchor_tag = logo_anchor[0]
      expect(anchor_tag).to include('target="_blank"')
      expect(anchor_tag).to match(/rel="[^"]*noopener[^"]*"/)
      expect(anchor_tag).to match(/rel="[^"]*noreferrer[^"]*"/)
    end
  end
end
