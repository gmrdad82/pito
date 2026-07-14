# frozen_string_literal: true

Rails.application.config.to_prepare do
  Pito::Achievements::Config.reload!
end
