class Bundle
  # "Which channels would best cover this bundle?"
  class ChannelRecommendation
    def self.recommend(bundle:, k: 10)
      raise NotImplementedError, "Bundle::ChannelRecommendation pending implementation"
    end
  end
end
