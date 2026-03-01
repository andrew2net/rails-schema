# frozen_string_literal: true

# Minimal Mongoid stubs for testing without a MongoDB connection.
# These mimic the interfaces that the Mongoid extractors rely on.

module Mongoid
  module Document; end

  # Stub for Mongoid::Boolean since Mongoid defines its own Boolean type
  class Boolean # rubocop:disable Lint/EmptyClass
  end

  module Association
    module Referenced
      class HasMany # rubocop:disable Lint/EmptyClass
      end

      class HasOne # rubocop:disable Lint/EmptyClass
      end

      class BelongsTo # rubocop:disable Lint/EmptyClass
      end

      class HasAndBelongsToMany # rubocop:disable Lint/EmptyClass
      end
    end

    module Embedded
      class EmbedsMany # rubocop:disable Lint/EmptyClass
      end

      class EmbedsOne # rubocop:disable Lint/EmptyClass
      end

      class EmbeddedIn # rubocop:disable Lint/EmptyClass
      end
    end
  end
end

module BSON
  class ObjectId # rubocop:disable Lint/EmptyClass
  end
end

# Stub field object matching Mongoid::Fields::Standard interface
StubField = Struct.new(:name, :type, :default_val)

# Stub validator for presence validation
StubPresenceValidator = Struct.new(:attributes) do
  def self.name
    "ActiveModel::Validations::PresenceValidator"
  end

  def class
    StubPresenceValidator
  end
end

# Stub relation metadata matching Mongoid association metadata interface
StubRelation = Struct.new(:relation_class, :class_name, :foreign_key, :polymorphic, :as, :key) do
  def class
    relation_class
  end

  def polymorphic?
    polymorphic || false
  end
end

# --- Test Models ---

class MongoidUser
  include Mongoid::Document

  def self.name
    "MongoidUser"
  end

  def self.collection_name
    "mongoid_users"
  end

  def self.fields
    {
      "_id" => StubField.new("_id", BSON::ObjectId, nil),
      "name" => StubField.new("name", String, nil),
      "email" => StubField.new("email", String, nil),
      "age" => StubField.new("age", Integer, 0),
      "active" => StubField.new("active", Mongoid::Boolean, true)
    }
  end

  def self.validators_on(field_name)
    required_fields = %w[name]
    return [StubPresenceValidator.new([field_name])] if required_fields.include?(field_name.to_s)

    []
  end

  def self.relations
    {
      "posts" => StubRelation.new(
        Mongoid::Association::Referenced::HasMany,
        "MongoidPost",
        "user_id",
        nil, nil, "posts"
      ),
      "profile" => StubRelation.new(
        Mongoid::Association::Embedded::EmbedsOne,
        "MongoidProfile",
        nil,
        nil, nil, "profile"
      )
    }
  end
end

class MongoidPost
  include Mongoid::Document

  def self.name
    "MongoidPost"
  end

  def self.collection_name
    "mongoid_posts"
  end

  def self.fields
    {
      "_id" => StubField.new("_id", BSON::ObjectId, nil),
      "title" => StubField.new("title", String, nil),
      "body" => StubField.new("body", String, nil),
      "user_id" => StubField.new("user_id", BSON::ObjectId, nil),
      "published_at" => StubField.new("published_at", Time, nil),
      "tags" => StubField.new("tags", Array, -> { [] })
    }
  end

  def self.validators_on(field_name)
    required_fields = %w[title user_id]
    return [StubPresenceValidator.new([field_name])] if required_fields.include?(field_name.to_s)

    []
  end

  def self.relations
    {
      "user" => StubRelation.new(
        Mongoid::Association::Referenced::BelongsTo,
        "MongoidUser",
        "user_id",
        nil, nil, "user"
      ),
      "comments" => StubRelation.new(
        Mongoid::Association::Embedded::EmbedsMany,
        "MongoidComment",
        nil,
        nil, nil, "comments"
      )
    }
  end
end

class MongoidComment
  include Mongoid::Document

  def self.name
    "MongoidComment"
  end

  def self.collection_name
    "mongoid_comments"
  end

  def self.fields
    {
      "_id" => StubField.new("_id", BSON::ObjectId, nil),
      "body" => StubField.new("body", String, nil),
      "rating" => StubField.new("rating", Float, nil)
    }
  end

  def self.validators_on(field_name)
    required_fields = %w[body]
    return [StubPresenceValidator.new([field_name])] if required_fields.include?(field_name.to_s)

    []
  end

  def self.relations
    {
      "post" => StubRelation.new(
        Mongoid::Association::Embedded::EmbeddedIn,
        "MongoidPost",
        nil,
        nil, nil, "post"
      )
    }
  end
end

class MongoidProfile
  include Mongoid::Document

  def self.name
    "MongoidProfile"
  end

  def self.collection_name
    "mongoid_profiles"
  end

  def self.fields
    {
      "_id" => StubField.new("_id", BSON::ObjectId, nil),
      "bio" => StubField.new("bio", String, nil)
    }
  end

  def self.validators_on(_field_name)
    []
  end

  def self.relations
    {
      "user" => StubRelation.new(
        Mongoid::Association::Embedded::EmbeddedIn,
        "MongoidUser",
        nil,
        nil, nil, "user"
      )
    }
  end
end
