# frozen_string_literal: true

RSpec.describe Rails::Schema::Extractor::AssociationReader do
  subject(:reader) { described_class.new }

  describe "#read" do
    it "reads has_many associations" do
      assocs = reader.read(User)
      posts_assoc = assocs.find { |a| a[:label] == "posts" }

      expect(posts_assoc).to include(
        from: "User",
        to: "Post",
        association_type: "has_many"
      )
    end

    it "reads belongs_to associations" do
      assocs = reader.read(Post)
      user_assoc = assocs.find { |a| a[:label] == "user" }

      expect(user_assoc).to include(
        from: "Post",
        to: "User",
        association_type: "belongs_to"
      )
    end

    it "skips polymorphic belongs_to" do
      assocs = reader.read(Comment)
      commentable = assocs.find { |a| a[:label] == "commentable" }

      expect(commentable).to be_nil
    end

    it "detects polymorphic has_many (as:)" do
      assocs = reader.read(Post)
      comments_assoc = assocs.find { |a| a[:label] == "comments" }

      expect(comments_assoc[:polymorphic]).to eq(true)
    end

    it "reads has_and_belongs_to_many" do
      assocs = reader.read(Post)
      tags_assoc = assocs.find { |a| a[:label] == "tags" }

      expect(tags_assoc).to include(
        association_type: "has_and_belongs_to_many",
        to: "Tag"
      )
    end

    it "includes foreign_key" do
      assocs = reader.read(Post)
      user_assoc = assocs.find { |a| a[:label] == "user" }

      expect(user_assoc[:foreign_key]).to eq("user_id")
    end
  end
end
