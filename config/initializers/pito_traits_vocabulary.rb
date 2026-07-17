# frozen_string_literal: true

Rails.application.config.to_prepare do
  Game::Traits::Vocabulary.reload!
end
