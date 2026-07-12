# frozen_string_literal: true

require "rails_helper"

RSpec.describe Ai::Web::Fetch, type: :service do
  let(:public_ip) { "93.184.216.34" }

  # DNS is stubbed per-host — the module resolves every hop's host itself
  # (that's the SSRF wall under test); WebMock covers only the transport.
  def resolve(host, to:)
    allow(Resolv).to receive(:getaddress).with(host).and_return(to)
  end

  describe ".call" do
    context "happy path" do
      let(:html) do
        <<~HTML
          <html>
            <head>
              <title>  Example Page  </title>
              <style>body { color: red }</style>
            </head>
            <body>
              <nav>Nav junk</nav>
              <script>evil()</script>
              <p>Hello    world</p>



              <p>Second paragraph</p>
              <footer>Footer junk</footer>
            </body>
          </html>
        HTML
      end

      it "fetches the page, strips chrome nodes, squeezes whitespace, and extracts the title" do
        resolve("example.com", to: public_ip)
        stub_request(:get, "https://example.com/article").to_return(status: 200, body: html)

        result = described_class.call(url: "https://example.com/article")

        expect(result[:title]).to eq("Example Page")
        expect(result[:url]).to eq("https://example.com/article")
        expect(result[:text]).to include("Hello world") # run of spaces squeezed to one
        expect(result[:text]).to include("Second paragraph")
        expect(result[:text]).not_to match(/\n{3,}/) # blank-line runs squeezed
        expect(result[:text]).not_to include("evil()", "color: red", "Nav junk", "Footer junk")
      end
    end

    context "SSRF wall — private/loopback/link-local/ULA/unspecified resolutions" do
      [ "127.0.0.1", "10.0.0.5", "192.168.1.10", "169.254.169.254", "fd00::1", "0.0.0.0" ].each do |address|
        it "refuses a host resolving to #{address} without issuing a request" do
          resolve("evil.example", to: address)

          expect(described_class.call(url: "http://evil.example/steal")).to eq(error: "address not allowed")
          expect(WebMock).not_to have_requested(:get, "http://evil.example/steal")
        end
      end
    end

    context "scheme and parse guards" do
      it "rejects non-http(s) schemes" do
        expect(described_class.call(url: "ftp://example.com/file.txt")).to eq(error: "only http(s) urls")
      end

      it "rejects an unparseable url as unreachable" do
        expect(described_class.call(url: "not a url at all")).to eq(error: "unreachable url")
      end

      it "rejects a blank url" do
        expect(described_class.call(url: "   ")).to eq(error: "only http(s) urls")
      end

      it "returns unreachable url when DNS resolution fails" do
        allow(Resolv).to receive(:getaddress).with("nxdomain.example").and_raise(Resolv::ResolvError)

        expect(described_class.call(url: "http://nxdomain.example/")).to eq(error: "unreachable url")
      end
    end

    context "redirects" do
      it "follows a redirect, re-resolving and re-checking the NEW host" do
        resolve("start.example", to: public_ip)
        resolve("next.example", to: "93.184.216.35")
        stub_request(:get, "http://start.example/a")
          .to_return(status: 301, headers: { "Location" => "http://next.example/b" })
        stub_request(:get, "http://next.example/b").to_return(
          status: 200,
          body:   "<html><head><title>Landed</title></head><body>Final text</body></html>"
        )

        result = described_class.call(url: "http://start.example/a")

        expect(result[:title]).to eq("Landed")
        expect(result[:url]).to eq("http://next.example/b")
        expect(result[:text]).to include("Final text")
        expect(Resolv).to have_received(:getaddress).with("next.example")
      end

      it "refuses a public → private redirect (the classic SSRF bounce)" do
        resolve("start.example", to: public_ip)
        resolve("internal.example", to: "10.0.0.5")
        stub_request(:get, "http://start.example/a")
          .to_return(status: 302, headers: { "Location" => "http://internal.example/admin" })

        expect(described_class.call(url: "http://start.example/a")).to eq(error: "address not allowed")
        expect(WebMock).not_to have_requested(:get, "http://internal.example/admin")
      end

      it "gives up after MAX_REDIRECTS hops" do
        resolve("loop.example", to: public_ip)
        stub_request(:get, "http://loop.example/")
          .to_return(status: 302, headers: { "Location" => "http://loop.example/" })

        expect(described_class.call(url: "http://loop.example/")).to eq(error: "too many redirects")
        expect(WebMock).to have_requested(:get, "http://loop.example/")
          .times(described_class::MAX_REDIRECTS + 1)
      end
    end

    it "caps extracted text at MAX_CHARS" do
      resolve("example.com", to: public_ip)
      stub_request(:get, "http://example.com/long").to_return(
        status: 200,
        body:   "<html><body><p>#{'a' * 10_000}</p></body></html>"
      )

      result = described_class.call(url: "http://example.com/long")

      expect(result[:text].length).to eq(described_class::MAX_CHARS)
    end

    it "returns the HTTP status on a non-success, non-redirect response" do
      resolve("example.com", to: public_ip)
      stub_request(:get, "http://example.com/missing").to_return(status: 404, body: "")

      expect(described_class.call(url: "http://example.com/missing")).to eq(error: "fetch failed (HTTP 404)")
    end
  end
end
