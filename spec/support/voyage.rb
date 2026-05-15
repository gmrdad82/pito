# Phase 29 — Voyage AI test fixtures.
#
# Real-API safety guarantee: in `Rails.env.test?` (which covers CI —
# `RAILS_ENV=test` there too), `WebMock.disable_net_connect!` in
# `spec/rails_helper.rb` blocks every non-localhost HTTP request,
# including the Voyage embeddings endpoint at `api.voyageai.com`.
# Specs that need to exercise Voyage logic opt in by calling
# `stub_voyage_embed` (or the lower-level `stub_voyage_credentials_key`
# helper inline in `spec/jobs/notes/embed_job_spec.rb`).
#
# After the flat credentials consolidation (a single
# `voyage.api_key` shared across environments), the test env can see a
# present key in credentials — the no-op-on-blank path inside
# `Notes::EmbedJob#call_voyage` is therefore NO LONGER the test
# guardrail. WebMock is. If you find this module's helpers unused while
# a spec sends real Voyage traffic, the spec is wrong, not WebMock.
#
# Surface:
#
#   * `stub_voyage_credentials_key(value)`
#     Stubs `Rails.application.credentials.dig(:voyage, :api_key)` to
#     return `value`. Use this when the spec only cares about the
#     credentials-presence gate (`AppSetting.voyage_configured?`) and
#     not about issuing an HTTP call.
#
#   * `stub_voyage_embed(vector: Array.new(1024) { 0.0 }, status: 200)`
#     Registers a WebMock stub for the Voyage embeddings POST endpoint
#     and returns a canned JSON shape (`{ data: [{ embedding: vector }] }`).
#     Use this from any spec exercising `Notes::EmbedJob`'s
#     happy-path "call Voyage and write the embedding" branch.
#
#   * shared context `"with Voyage stubbed"` — convenience wrapper
#     that combines a credentials-key stub + the embed stub in one
#     `include_context` line. Defaults: key `"vk_test_stubbed"`, vector
#     of 1024 zeros, HTTP 200.
#
# Naming mirrors `spec/support/google_stubs.rb`.
module VoyageStubs
  VOYAGE_EMBED_URL = "https://api.voyageai.com/v1/embeddings".freeze

  module_function

  # Stub `Rails.application.credentials.dig(:voyage, :api_key)` to
  # `value`. Pass `nil` / `""` to simulate "no key configured" and the
  # blank-key short-circuit branch.
  def stub_voyage_credentials_key(value)
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig)
      .with(:voyage, :api_key).and_return(value)
  end

  # Register a WebMock stub for the Voyage embeddings POST endpoint.
  # Returns the WebMock stub object so callers can chain extra
  # expectations (`.to_raise`, `.to_timeout`, etc.) if needed.
  def stub_voyage_embed(vector: Array.new(1024) { 0.0 }, status: 200)
    body = { data: [ { embedding: vector } ] }.to_json
    WebMock.stub_request(:post, VOYAGE_EMBED_URL)
      .to_return(
        status: status,
        body: body,
        headers: { "Content-Type" => "application/json" }
      )
  end
end

RSpec.shared_context "with Voyage stubbed" do
  let(:voyage_stub_key) { "vk_test_stubbed" }
  let(:voyage_stub_vector) { Array.new(1024) { 0.0 } }

  before do
    VoyageStubs.stub_voyage_credentials_key(voyage_stub_key)
    VoyageStubs.stub_voyage_embed(vector: voyage_stub_vector)
  end
end
