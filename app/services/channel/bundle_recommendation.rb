class Channel
  # "Which bundles should this channel consider?"
  class BundleRecommendation
    def self.recommend(channel:, k: 10)
      raise NotImplementedError, "Channel::BundleRecommendation pending implementation"
    end
  end
end
