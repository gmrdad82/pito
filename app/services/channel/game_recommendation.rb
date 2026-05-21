class Channel
  # "Which games should this channel cover next?"
  # Input: a Channel. Output: ranked list of Games.
  class GameRecommendation
    # @param channel [Channel]
    # @param k [Integer] top K games to return
    # @return [Array<Hash>] [{ game:, score:, bucket: }, ...]
    def self.recommend(channel:, k: 10)
      raise NotImplementedError, "Channel::GameRecommendation pending implementation"
    end
  end
end
