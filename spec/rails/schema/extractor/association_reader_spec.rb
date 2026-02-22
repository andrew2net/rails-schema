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

    context "when build_association_data raises" do
      it "warns and excludes the broken association" do
        bad_klass = double("Klass", name: "Bogus")
        bad_ref = double("reflection",
                         macro: :has_many,
                         name: :broken,
                         options: {},
                         klass: bad_klass,
                         class_name: "Bogus")
        allow(bad_ref).to receive(:foreign_key).and_raise(StandardError, "kaboom")

        model = double("Model", name: "Foo",
                                reflect_on_all_associations: [bad_ref])

        assocs = nil
        expect do
          assocs = reader.read(model)
        end.to output(/Could not read association broken on Foo/).to_stderr

        expect(assocs).to eq([])
      end
    end

    context "when target_model_name raises" do
      it "warns and falls back to class_name" do
        bad_ref = double("reflection",
                         macro: :belongs_to,
                         name: :author,
                         class_name: "Author",
                         options: {},
                         foreign_key: "author_id")
        allow(bad_ref).to receive(:klass).and_raise(StandardError, "no table")

        model = double("Model", name: "Article",
                                reflect_on_all_associations: [bad_ref])

        assocs = nil
        expect do
          assocs = reader.read(model)
        end.to output(/Could not resolve target for author/).to_stderr

        expect(assocs.first[:to]).to eq("Author")
      end
    end
  end
end
