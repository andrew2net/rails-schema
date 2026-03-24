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

| Layer | Responsibility | Key Classes |
|---|---|---|
| **Extractor** | Introspects Rails environment; collects models, columns, associations | `ModelScanner`, `PackwerkDiscovery`, `ColumnReader`, `AssociationReader`, `SchemaFileParser`, `StructureSqlParser`, plus `Mongoid::ModelScanner`, `Mongoid::ModelAdapter`, `Mongoid::ColumnReader`, `Mongoid::AssociationReader` |
| **Transformer** | Normalizes extracted data into a serializable graph (nodes + edges + metadata) | `GraphBuilder`, `Node`, `Edge` |
| **Renderer** | Injects graph data into an HTML/JS/CSS template via ERB | `HtmlGenerator` |
| **Railtie** | Provides the `rails_schema:generate` rake task | `Railtie` |

### Key Paths

- `lib/rails/schema.rb` — entry point, `generate` dispatches to ActiveRecord or Mongoid pipeline
- `lib/rails/schema/extractor/` — model discovery, column/association reading, schema file parsing
- `lib/rails/schema/extractor/mongoid/` — Mongoid-specific extractors
- `lib/rails/schema/transformer/` — builds normalized graph JSON
- `lib/rails/schema/renderer/` — ERB-based HTML generation with inlined JS/CSS/data
- `lib/rails/schema/assets/` — frontend (vanilla JS + d3-force, CSS, HTML template)

### Generation Pipeline

```ruby
def generate(output: nil)
  schema_data = parse_schema
  models = Extractor::ModelScanner.new(schema_data: schema_data).scan
  column_reader = Extractor::ColumnReader.new(schema_data: schema_data)
  graph_data = Transformer::GraphBuilder.new(column_reader: column_reader).build(models)
  Renderer::HtmlGenerator.new(graph_data: graph_data).render_to_file(output)
end
```

### Data Extraction Strategy

1. **`db/schema.rb`** — `SchemaFileParser` parses with regex (table names, columns, types, nullable, defaults, PKs)
2. **`db/structure.sql`** — `StructureSqlParser` parses SQL `CREATE TABLE` statements, maps SQL types to Rails types
3. **ActiveRecord reflection API** — `AssociationReader` uses `reflect_on_all_associations` for associations
4. **`Model.columns`** — `ColumnReader` falls back to this when table not found in schema_data

### Model Discovery

`ModelScanner` (ActiveRecord):
1. Discovers model directories: `app/models` + Packwerk package dirs via `PackwerkDiscovery`
2. Eager-loads via Zeitwerk `eager_load_dir` for each model directory; falls back to `loader.eager_load` if no concrete models found, then `Rails.application.eager_load!`, then per-file `require`
3. Collects `ActiveRecord::Base.descendants`
4. Filters: abstract classes, anonymous classes, models without known tables
5. Applies `exclude_models` config (supports wildcard prefix like `"ActiveStorage::*"`) and `exclude_model_if` proc

`PackwerkDiscovery`:
1. Reads `packwerk.yml` from `Rails.root` for `package_paths` glob patterns
2. Finds directories with `package.yml` under those paths
3. Returns `app/models` and `app/public` paths for each package

`Mongoid::ModelScanner`:
1. Eager-loads via Zeitwerk or file glob with fallbacks
2. Scans `ObjectSpace` for `Mongoid::Document` includers
3. Also loads models from mounted Rails engines
4. Returns models wrapped in `ModelAdapter` for GraphBuilder compatibility

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
- CI matrix: Ruby 2.7, 3.0, 3.1, 3.2, 3.3, 3.4
- Mongoid specs stub `Rails::Engine` and `Rails::Application` since they may not exist in test env
- SimpleCov is enabled; coverage report goes to `coverage/`

## Frontend

Single self-contained HTML file — no CDN, no network requests. D3 is vendored/minified.

- **Vanilla JS + d3-force** for graph rendering
- **CSS custom properties** for dark/light theming
- Features: searchable sidebar, click-to-focus, double-click to isolate neighborhood, detail panel, zoom/pan, keyboard shortcuts (`/` search, `Esc` deselect, `+/-` zoom, `F` fit), Mermaid ER diagram export (`.mmd`) filtered by sidebar visibility
- **Select All smart toggle** — when all models are already selected and a search filter is active, "Select All" narrows to only filtered models (acts as "select only these"); otherwise it adds filtered models to the current selection

## Design Decisions

- **Single HTML file** — zero deployment friction, offline-first, portable (CI, GitHub Pages, email)
- **Not a mounted engine** — static file works without a running server
- **Parse schema files** — works without DB connection (CI environments, no local DB)
- **Force-directed layout** — handles unknown schemas gracefully without pre-defined positions
- **Node layout categories** — three-way partition in `app.js`: connected nodes use force simulation, self-ref-only models (all edges point to themselves) are placed in a vertical left column via `layoutSelfRefNodes()`, true orphans (zero edges) are placed in rows above the diagram via `layoutOrphans()`
- **Edge deduplication** — `GraphBuilder.deduplicate_edges` chains two passes: (1) HABTM dedup merges symmetric `has_and_belongs_to_many` pairs into one edge with `reverse_label`, (2) has_many/belongs_to dedup merges matching pairs (same foreign_key, reversed endpoints) into one edge where the has_many/has_one side is kept and the belongs_to label becomes `reverse_label` with its own `reverse_association_type`. The frontend uses `reverse_association_type` to color each label by its own association type.
