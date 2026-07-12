# frozen_string_literal: true

require "rails_helper"

RSpec.describe AiModelCatalogRefreshJob do
  it "busts + re-fetches every keyed provider plus keyless opencode" do
    AppSetting.set("anthropic_api_key", "sk-ant-test")

    refreshed = []
    allow(Ai::ModelCatalog).to receive(:bust!) { |provider:| refreshed << provider.to_sym }
    allow(Ai::ModelCatalog).to receive(:models).and_return([])

    described_class.perform_now

    expect(refreshed).to include(:opencode, :anthropic)
    expect(refreshed).not_to include(:openrouter, :deepseek, :qwen, :huggingface)
    # every busted provider is immediately re-fetched (cache re-warm)
    refreshed.each do |provider|
      expect(Ai::ModelCatalog).to have_received(:models).with(provider: provider)
    end
  end

  it "is scheduled nightly in both recurring blocks" do
    schedule = YAML.load_file(Rails.root.join("config/recurring.yml"))
    %w[production development].each do |env|
      entry = schedule.fetch(env).fetch("ai_model_catalog_refresh")
      expect(entry["class"]).to eq("AiModelCatalogRefreshJob")
      expect(entry["schedule"]).to eq("30 1 * * *")
    end
  end
end
