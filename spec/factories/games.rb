# frozen_string_literal: true

# Minimal factory for P6 model specs. Full traits added in P11.
FactoryBot.define do
  factory :game do
    sequence(:title) { |n| "Game #{n}" }
  end
end
