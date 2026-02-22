# Rails::Schema — Project Design

**A Ruby gem that generates an interactive HTML/JS/CSS page to visualize the database schema of a Rails application.**

---

## 1. Gem Overview

**Name:** `rails-schema`
**Module:** `Rails::Schema`
**Version:** `0.1.0`

Rails::Schema introspects a Rails app's models, associations, and database columns at runtime, then generates a single self-contained HTML file with an interactive, explorable entity-relationship diagram. No external server, no SaaS dependency — just one command and a browser.

```bash
# Rake task
rake rails_schema:generate

# Programmatic
Rails::Schema.generate(output: "docs/schema.html")
```

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────┐
│                   rails-schema gem                    │
├──────────────┬──────────────┬────────────────────────┤
│  Extractor   │  Transformer │  Renderer              │
│  (Ruby)      │  (Ruby)      │  (ERB → HTML/JS/CSS)   │
├──────────────┼──────────────┼────────────────────────┤
│ Reads Rails  │ Builds a     │ Produces a single      │
│ models,      │ normalized   │ self-contained .html   │
│ reflections, │ graph JSON   │ file with embedded     │
│ schema.rb,   │ structure    │ JS app + CSS           │
│ columns      │              │                        │
└──────────────┴──────────────┴────────────────────────┘
```

### 2.1 Layer Breakdown

| Layer | Responsibility | Key Classes |
|---|---|---|
| **Extractor** | Introspects Rails environment; collects models, columns, associations | `Rails::Schema::Extractor::ModelScanner`, `ColumnReader`, `AssociationReader`, `SchemaFileParser`, `StructureSqlParser` |
| **Transformer** | Normalizes extracted data into a serializable graph structure (nodes + edges + metadata) | `Rails::Schema::Transformer::GraphBuilder`, `Node`, `Edge` |
| **Renderer** | Takes the graph data and injects it into an HTML/JS/CSS template using ERB | `Rails::Schema::Renderer::HtmlGenerator` |
| **Railtie** | Provides the `rails_schema:generate` rake task | `Rails::Schema::Railtie` |

### 2.2 Generation Pipeline

```ruby
def generate(output: nil)
  schema_data = parse_schema
  models = Extractor::ModelScanner.new(schema_data: schema_data).scan
  column_reader = Extractor::ColumnReader.new(schema_data: schema_data)
  graph_data = Transformer::GraphBuilder.new(column_reader: column_reader).build(models)
  generator = Renderer::HtmlGenerator.new(graph_data: graph_data)
  generator.render_to_file(output)
end

def parse_schema
  case configuration.schema_format
  when :ruby then Extractor::SchemaFileParser.new.parse
  when :sql  then Extractor::StructureSqlParser.new.parse
  when :auto
    data = Extractor::SchemaFileParser.new.parse
    data.empty? ? Extractor::StructureSqlParser.new.parse : data
  end
end
```

---

## 3. Data Extraction Strategy

### 3.1 Sources of Truth

1. **`db/schema.rb` parsing** — `SchemaFileParser` parses the schema file line-by-line with regex to extract table names, column definitions (name, type, nullable, default), and primary key info. This is attempted first and used as a fast, database-free source.
2. **`db/structure.sql` parsing** — `StructureSqlParser` parses SQL `CREATE TABLE` statements for projects using `config.active_record.schema_format = :sql`. Maps SQL types to Rails-friendly types, detects `NOT NULL`, `DEFAULT` values, and primary keys. Handles schema-qualified names (`public.users`), timestamp precision (`timestamp(6)`), and both quoted and unquoted identifiers.
3. **ActiveRecord reflection API** — `AssociationReader` uses `Model.reflect_on_all_associations` for associations (`has_many`, `belongs_to`, `has_one`, `has_and_belongs_to_many`), including `:through` and `:polymorphic`.
4. **`Model.columns`** — `ColumnReader` falls back to `model.columns` via ActiveRecord when a table is not found in schema_data.

### 3.2 Model Discovery

`ModelScanner` discovers models by:

1. Calling `Rails.application.eager_load!` (with Zeitwerk support and multiple fallback strategies)
2. Collecting `ActiveRecord::Base.descendants`
3. Filtering out abstract classes, anonymous classes, and models without known tables
4. Applying `exclude_models` configuration (supports wildcard prefix matching like `"ActiveStorage::*"`)
5. Returning models sorted by name

When `schema_data` is available, table existence is checked against parsed schema data instead of hitting the database.

### 3.3 Schema File Parser

`SchemaFileParser` provides database-free column extraction:

- Parses `create_table` blocks from `db/schema.rb`
- Extracts column types, names, nullability, and defaults (string, numeric, boolean)
- Handles custom primary key types (`id: :uuid`, `id: :bigint`) and `id: false`
- Skips index definitions

### 3.4 Structure SQL Parser

`StructureSqlParser` provides database-free column extraction from SQL dumps:

- Parses `CREATE TABLE` statements from `db/structure.sql`
- Maps SQL types to Rails types (e.g. `character varying` → `string`, `bigint` → `bigint`, `timestamp without time zone` → `datetime`)
- Handles schema-qualified table names (`public.users` → `users`)
- Handles timestamp precision (`timestamp(6) without time zone`)
- Detects primary keys from `CONSTRAINT ... PRIMARY KEY` and inline `PRIMARY KEY`
- Extracts `NOT NULL`, `DEFAULT` values (strings, numbers, booleans)
- Skips constraint lines (`CONSTRAINT`, `UNIQUE`, `CHECK`, `FOREIGN KEY`, etc.)

### 3.5 Intermediate Data Format (JSON Graph)

```json
{
  "nodes": [
    {
      "id": "User",
      "table": "users",
      "columns": [
        { "name": "id", "type": "bigint", "primary": true },
        { "name": "email", "type": "string", "nullable": false },
        { "name": "name", "type": "string", "nullable": true }
      ]
    }
  ],
  "edges": [
    {
      "from": "User",
      "to": "Post",
      "type": "has_many",
      "through": null,
      "foreign_key": "user_id",
      "polymorphic": false,
      "label": "posts"
    }
  ],
  "metadata": {
    "rails_version": "7.2.0",
    "generated_at": "2026-02-15T12:00:00Z",
    "model_count": 42
  }
}
```

---

## 4. Interactive Frontend Design

The generated HTML file is a **single self-contained file** — no CDN dependencies, no network requests. All JS and CSS are inlined. The JSON graph is embedded as a `<script>` tag.

### 4.1 Technology Choices

| Concern | Choice | Rationale |
|---|---|---|
| Graph rendering | **SVG + d3-force** (vendored/minified) | DOM-level interactivity, good for typical schema sizes |
| Layout algorithm | Force-directed (d3-force) | Natural clustering of related models |
| UI framework | Vanilla JS | Zero dependencies, small file size |
| Styling | CSS custom properties + embedded stylesheet | Theming support, dark/light mode |

### 4.2 Implemented Interactive Features

#### A. Model Selector Panel (left sidebar, 280px)

- Searchable list of all models with filtering
- Multi-select checkboxes to toggle visibility
- Model count display

#### B. Canvas / Diagram Area (center)

- **Nodes** = model cards showing:
  - Model name (bold header)
  - Column list (expandable/collapsible — collapsed by default)
  - Primary key highlighted
  - Column types shown in a muted typeface
- **Edges** = association lines:
  - Color-coded by association type
  - Labels on hover (association name + foreign key)
- **Force-directed layout** that stabilizes, then allows manual drag-and-drop

#### C. Zoom & Navigation

- Scroll-wheel zoom with smooth interpolation
- Pinch-to-zoom on trackpads
- Fit-to-screen button
- Zoom-to-selection (click a model in sidebar to center on it)

#### D. Focus Mode

When a user clicks on a model node:

1. The selected model and its directly associated models are highlighted
2. All other nodes and edges fade to reduced opacity
3. A detail panel (right sidebar, 320px) shows full column/association info
4. Press `Esc` or click background to exit

#### E. Toolbar (48px)

- Dark / Light theme toggle (respects `prefers-color-scheme`)
- Fit-to-screen button
- Keyboard shortcuts: `/` to focus search, `Esc` to deselect

---

## 5. Configuration

```ruby
# config/initializers/rails_schema.rb
Rails::Schema.configure do |config|
  config.output_path    = "docs/schema.html"    # Output file location
  config.exclude_models = []                     # Models to exclude (supports "Namespace::*" wildcards)
  config.title          = "Database Schema"      # Page title
  config.theme          = :auto                  # :light, :dark, :auto
  config.expand_columns = false                  # Start with columns expanded
  config.schema_format  = :auto                  # :auto, :ruby, or :sql
end
```

---

## 6. Gem Structure

```
rails-schema/
├── lib/
│   ├── rails/schema.rb                    # Entry point, configuration DSL, generate method
│   └── rails/schema/
│       ├── version.rb                     # VERSION = "0.1.0"
│       ├── configuration.rb               # Config object (6 attributes)
│       ├── railtie.rb                     # Rails integration, rake task
│       ├── extractor/
│       │   ├── model_scanner.rb           # Discovers AR models
│       │   ├── association_reader.rb      # Reads reflections
│       │   ├── column_reader.rb           # Reads columns (schema_data or AR)
│       │   ├── schema_file_parser.rb      # Parses db/schema.rb
│       │   └── structure_sql_parser.rb   # Parses db/structure.sql
│       ├── transformer/
│       │   ├── graph_builder.rb           # Builds node/edge graph
│       │   ├── node.rb                    # Value object
│       │   └── edge.rb                    # Value object
│       ├── renderer/
│       │   └── html_generator.rb          # ERB rendering, asset inlining
│       └── assets/
│           ├── template.html.erb          # Main HTML template
│           ├── app.js                     # Interactive frontend (vanilla JS)
│           ├── style.css                  # Stylesheet with CSS custom properties
│           └── vendor/
│               └── d3.min.js              # Vendored d3 library
├── spec/
│   ├── spec_helper.rb
│   ├── support/
│   │   └── test_models.rb                # User, Post, Comment, Tag models
│   └── rails/schema/
│       ├── rails_schema_spec.rb
│       ├── configuration_spec.rb
│       ├── extractor/
│       │   ├── model_scanner_spec.rb
│       │   ├── column_reader_spec.rb
│       │   ├── association_reader_spec.rb
│       │   ├── schema_file_parser_spec.rb
│       │   └── structure_sql_parser_spec.rb
│       ├── transformer/
│       │   └── graph_builder_spec.rb
│       └── renderer/
│           └── html_generator_spec.rb
├── Gemfile
├── rails-schema.gemspec
├── LICENSE.txt
└── README.md
```

---

## 7. Key Design Decisions

### Why a single HTML file?

- **Zero deployment friction** — open in any browser, share via Slack/email, commit to repo
- **Offline-first** — works on airplane mode, no CDN failures
- **Portable** — CI can generate it, GitHub Pages can host it, anyone can view it

### Why not a mounted Rails engine?

A mounted engine requires a running server. A static file can be generated in CI, committed to the repo, and opened by anyone — including non-developers looking at a data model.

### Why parse schema.rb / structure.sql?

Parsing `db/schema.rb` or `db/structure.sql` allows column extraction without a database connection. This means the gem can work in CI environments or development setups where the database isn't running. It also avoids eager-loading the entire app just to read column metadata. The `schema_format: :auto` default tries `schema.rb` first, then falls back to `structure.sql`, so the gem works out of the box regardless of which format a project uses.

### Why force-directed layout?

It handles unknown schemas gracefully — you don't need to pre-define positions. Combined with drag-and-drop repositioning, it gives the best default experience.

---

## 8. Dependencies

```ruby
# rails-schema.gemspec
spec.add_dependency "activerecord", ">= 6.0"
spec.add_dependency "railties", ">= 6.0"

# Development
# rspec (~> 3.0), rubocop (~> 1.21), sqlite3
```

**Zero runtime JS dependencies shipped to the user** — d3 is vendored and minified into the template. The HTML file has no external requests.

---

## 9. Testing Strategy

| Layer | Approach |
|---|---|
| Extractor | Unit tests with in-memory SQLite models (User, Post, Comment, Tag) |
| Transformer | Pure Ruby unit tests — graph building, edge filtering |
| Renderer | Output tests — verify HTML structure, embedded data, script injection safety |
| Configuration | Unit tests for defaults and attribute setting |

**94 tests, all passing.** Run with `bundle exec rspec`.

---

## 10. Future Enhancements (Roadmap)

1. **CLI executable** — `bundle exec rails_schema` binary for standalone usage
2. **Live mode** — a mounted Rails engine with hot-reload when migrations run
3. **Additional layout modes** — hierarchical, circular, grid
4. **Validation extraction** — read `Model.validators` for presence, uniqueness constraints
5. **STI handling** — group models sharing a table, show children as badges
6. **Concern extraction** — display included modules on model nodes
7. **Export options** — PNG, SVG, Mermaid ER diagram, raw JSON
8. **Schema diff** — compare two generated JSONs and highlight changes
9. **Multi-database support** — Rails 6+ multi-DB configs
10. **Minimap** — thumbnail overview for large schemas
11. **Permalink / State URL** — encode view state in URL hash for sharing
12. **Advanced filtering** — `include_only`, namespace grouping, tag-based filters
13. **Custom CSS/JS injection** — user-provided assets inlined into output

---

*Document reflects the current implementation (v0.1.0). Future enhancements are aspirational and subject to refinement.*
