# frozen_string_literal: true

require "net/http"

module Ai
  module Web
    # The AI's web_search tool backend — Tavily (https://tavily.com). One
    # POST per query against the owner's own API key, stored via
    # `/config tavily api_key=…`. Free tier: ~1k queries/month, no card.
    #
    # Returns up to RESULTS entries of { title:, url:, snippet: } — or
    # { error: } (never raises into the orchestrator loop). Results are
    # UNTRUSTED DATA for the model, never instructions — the toolset
    # description carries that framing.
    module Search
      module_function

      ENDPOINT     = "https://api.tavily.com/search"
      RESULTS      = 5
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10

      def configured?
        AppSetting.get("tavily_api_key").present?
      end

      # @param query [String]
      # @return [Hash] { results: [{title:, url:, snippet:}, …] } | { error: String }
      def call(query:)
        q = query.to_s.strip
        return { error: "empty query" } if q.blank?
        return { error: "web search isn't configured (/config tavily api_key=…)" } unless configured?

        uri = URI.parse(ENDPOINT)
        response = Net::HTTP.start(uri.hostname, uri.port,
                                   use_ssl: true,
                                   open_timeout: OPEN_TIMEOUT,
                                   read_timeout: READ_TIMEOUT) do |http|
          request = Net::HTTP::Post.new(uri)
          request["Content-Type"] = "application/json"
          request.body = {
            api_key:     AppSetting.get("tavily_api_key"),
            query:       q,
            max_results: RESULTS
          }.to_json
          http.request(request)
        end

        return { error: "search failed (HTTP #{response.code})" } unless response.is_a?(Net::HTTPSuccess)

        results = Array(JSON.parse(response.body)["results"]).first(RESULTS).map do |item|
          {
            title:   item["title"].to_s,
            url:     item["url"].to_s,
            snippet: item["content"].to_s
          }
        end
        { results: results }
      rescue StandardError => e
        Rails.logger.warn("[Ai::Web::Search] #{e.class}: #{e.message}")
        { error: "search failed (#{e.class})" }
      end
    end
  end
end
