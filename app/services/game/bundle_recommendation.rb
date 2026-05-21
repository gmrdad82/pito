class Game
  # "Which bundles include this game, ranked by relevance?"
  class BundleRecommendation
    def self.recommend(game:, k: 10)
      raise NotImplementedError, "Game::BundleRecommendation pending implementation"
    end
  end
end
