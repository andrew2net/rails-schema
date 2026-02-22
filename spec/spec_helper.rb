# frozen_string_literal: true

require "simplecov"
SimpleCov.start

require "active_record"

ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

ActiveRecord::Schema.define do
  create_table :users do |t|
    t.string :name, null: false
    t.string :email, null: false
    t.timestamps
  end

  create_table :posts do |t|
    t.references :user, null: false
    t.string :title, null: false
    t.text :body
    t.timestamps
  end

  create_table :comments do |t|
    t.references :commentable, polymorphic: true, null: false
    t.text :body, null: false
    t.timestamps
  end

  create_table :tags do |t|
    t.string :name, null: false
  end

  create_table :posts_tags, id: false do |t|
    t.references :post, null: false
    t.references :tag, null: false
  end
end

require "rails/schema"
require_relative "support/test_models"

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:each) do
    Rails::Schema.reset_configuration!
  end
end
