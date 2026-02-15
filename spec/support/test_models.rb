# frozen_string_literal: true

class User < ActiveRecord::Base
  has_many :posts
end

class Post < ActiveRecord::Base
  belongs_to :user
  has_many :comments, as: :commentable
  has_and_belongs_to_many :tags
end

class Comment < ActiveRecord::Base
  belongs_to :commentable, polymorphic: true
end

class Tag < ActiveRecord::Base
  has_and_belongs_to_many :posts
end
