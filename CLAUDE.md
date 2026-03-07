# CLAUDE.md — Project Instructions for Claude Code

## Project

`rails-schema` — a Ruby gem that generates an interactive HTML entity-relationship diagram from a Rails app's models, associations, and columns. Single self-contained HTML output, no server needed.

## Quick Commands

```bash
bundle exec rspec          # Run all tests
bundle exec rubocop        # Run linter
bundle exec rspec spec/rails/schema/extractor/mongoid/  # Mongoid tests only
```

## Architecture

Three-layer pipeline: **Extractor → Transformer → Renderer**

- `lib/rails/schema.rb` — entry point, `generate` dispatches to ActiveRecord or Mongoid pipeline
- `lib/rails/schema/extractor/` — model discovery, column/association reading, schema file parsing
- `lib/rails/schema/extractor/mongoid/` — Mongoid-specific extractors (model_scanner, model_adapter, column_reader, association_reader)
- `lib/rails/schema/transformer/` — builds normalized graph JSON (nodes + edges + metadata)
- `lib/rails/schema/renderer/` — ERB-based HTML generation with inlined JS/CSS/data
- `lib/rails/schema/assets/` — frontend (vanilla JS + d3-force, CSS, HTML template)

## Key Conventions

- Ruby >= 2.7, Rails >= 5.2
- Double quotes for strings (RuboCop enforced)
- RuboCop max method length: 15 lines, default ABC/complexity limits
- No `Style/Documentation` required
- `spec/support/test_models.rb` — ActiveRecord test models (User, Post, Comment, Tag)
- `spec/support/mongoid_test_models.rb` — Mongoid test models (MongoidUser, MongoidPost, MongoidComment)
- Tests use in-memory SQLite for ActiveRecord, stubbed Mongoid::Document for Mongoid
- `config.before(:each) { Rails::Schema.reset_configuration! }` in spec_helper

## Schema Formats

`config.schema_format` supports: `:auto`, `:ruby`, `:sql`, `:mongoid`

- `:auto` — tries schema.rb, falls back to structure.sql; auto-detects Mongoid if `Mongoid::Document` is defined
- `:mongoid` — runtime introspection of Mongoid models (no schema file needed)

## Testing Notes

- Always run `bundle exec rubocop` before committing — CI checks both tests and linting
- Mongoid specs stub `Rails::Engine` and `Rails::Application` since they may not exist in test env
- SimpleCov is enabled; coverage report goes to `coverage/`
