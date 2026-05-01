require "rails_helper"

RSpec.describe "Postgres extensions" do
  let(:connection) { ActiveRecord::Base.connection }

  it "has pgcrypto enabled" do
    expect(connection.extension_enabled?("pgcrypto")).to be true
  end

  it "has citext enabled" do
    expect(connection.extension_enabled?("citext")).to be true
  end

  it "has vector enabled" do
    expect(connection.extension_enabled?("vector")).to be true
  end
end
