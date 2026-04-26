FactoryBot.define do
  factory :note do
    title { Faker::Lorem.sentence(word_count: 3) }
    body { Faker::Lorem.paragraphs(number: 2).join("\n\n") }
    kind { :idea }
  end
end
