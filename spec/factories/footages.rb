FactoryBot.define do
  factory :footage do
    project
    tenant { project.tenant }
    kind { :a_roll }
    source { :obs }
    sequence(:local_path) { |n| "/tmp/footage/clip-#{n}.mp4" }
    sequence(:filename)   { |n| "clip-#{n}.mp4" }
    bit_depth { 8 }
    has_commentary_track { false }

    trait :with_game do
      after(:build) do |footage|
        game = create(:game, tenant: footage.tenant)
        footage.game = game
        footage.platform = game.platforms.first["platform"]
      end
    end
  end
end
