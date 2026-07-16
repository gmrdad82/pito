# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::BadRequestGuard do
  # `app` (the fake Rack inner app) is defined per-context below.
  let(:middleware) { described_class.new(app) }
  let(:env) { {} }

  Pito::BadRequestGuard::MALFORMED_REQUEST_ERRORS.each do |error_class|
    context "when the inner app raises #{error_class}" do
      let(:app) { ->(_env) { raise error_class, "boom" } }

      it "returns a 400 Bad Request response instead of propagating" do
        status, headers, body = middleware.call(env)

        expect(status).to eq(400)
        expect(headers).to eq({ "content-type" => "text/plain; charset=utf-8" })
        expect(body).to eq([ "Bad Request\n" ])
      end
    end
  end

  context "when the inner app succeeds" do
    let(:app) { ->(_env) { [ 200, {}, [ "ok" ] ] } }

    it "passes the response through unchanged" do
      expect(middleware.call(env)).to eq([ 200, {}, [ "ok" ] ])
    end
  end

  context "when the inner app raises an unrelated error" do
    let(:app) { ->(_env) { raise RuntimeError, "unrelated failure" } }

    it "does not swallow the error" do
      expect { middleware.call(env) }.to raise_error(RuntimeError, "unrelated failure")
    end
  end
end
