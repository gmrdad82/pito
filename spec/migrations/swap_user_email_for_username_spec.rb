require "rails_helper"
require Rails.root.join(
  "db/migrate/20260514185800_swap_user_email_for_username.rb"
)

# Phase 29 — Unit A2. Drives the email→username column-swap migration
# against the live test DB. `users.email` + `index_users_on_email` are
# gone; `users.username` (citext, NOT NULL) + a unique
# `index_users_on_username` exist. The `around` hook leaves the test
# DB in the post-migration state regardless of mid-example failure so
# neighbour specs keep working.
RSpec.describe SwapUserEmailForUsername, type: :model do
  def column_for(name)
    ActiveRecord::Base.connection.columns(:users).find { |c| c.name == name.to_s }
  end

  def index_names
    ActiveRecord::Base.connection.indexes(:users).map(&:name)
  end

  describe "post-migration state" do
    it "has dropped the email column" do
      expect(column_for(:email)).to be_nil
    end

    it "has dropped index_users_on_email" do
      expect(index_names).not_to include("index_users_on_email")
    end

    it "has a username column that is citext and NOT NULL" do
      col = column_for(:username)
      expect(col).not_to be_nil
      expect(col.sql_type).to eq("citext")
      expect(col.null).to be(false)
    end

    it "has a unique index_users_on_username" do
      idx = ActiveRecord::Base.connection.indexes(:users)
                              .find { |i| i.name == "index_users_on_username" }
      expect(idx).not_to be_nil
      expect(idx.unique).to be(true)
      expect(idx.columns).to eq(%w[username])
    end
  end

  describe "rollback + re-apply" do
    around do |example|
      # Empty `users` so `down` (which re-adds `email` NOT NULL) and
      # `up` (which re-adds `username` NOT NULL) both apply cleanly.
      Session.delete_all
      User.delete_all
      example.run
    ensure
      described_class.new.migrate(:up) if column_for(:username).nil?
    end

    it "restores email on `down` and swaps back to username on `up`" do
      described_class.new.migrate(:down)
      expect(column_for(:email)).not_to be_nil
      expect(column_for(:username)).to be_nil
      expect(index_names).to include("index_users_on_email")

      described_class.new.migrate(:up)
      expect(column_for(:username)).not_to be_nil
      expect(column_for(:email)).to be_nil
      expect(index_names).to include("index_users_on_username")
    end
  end
end
