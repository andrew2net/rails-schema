# SchemaVision — High-Level Design

**A Ruby gem that generates an interactive HTML/JS/CSS page to visualize the database schema of a Rails application.**

---

## 1. Gem Overview

**Name:** `schema_vision`
**Tagline:** *"Your Rails schema, alive."*

SchemaVision introspects a Rails app's models, associations, and database columns at runtime, then generates a single self-contained HTML file with an interactive, explorable entity-relationship diagram. No external server, no SaaS dependency — just one command and a browser.

```bash
# CLI usage
bundle exec schema_vision

# Rake task
rake schema_vision:generate

# Programmatic
SchemaVision.generate(output: "docs/schema.html")
```

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────┐
│                   schema_vision gem                   │
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
| **Extractor** | Introspects Rails environment; collects models, columns, associations, indices, validations | `SchemaVision::Extractor::ModelScanner`, `SchemaVision::Extractor::SchemaReader` |
| **Transformer** | Normalizes extracted data into a serializable graph structure (nodes + edges + metadata) | `SchemaVision::Transformer::GraphBuilder` |
| **Renderer** | Takes the graph JSON and injects it into an HTML/JS/CSS template using ERB | `SchemaVision::Renderer::HtmlGenerator` |
| **CLI / Railtie** | Provides `rake` tasks, a CLI binary, and Rails integration | `SchemaVision::Railtie`, `SchemaVision::CLI` |

---

## 3. Data Extraction Strategy

### 3.1 Sources of Truth (in priority order)

1. **ActiveRecord reflection API** — `Model.reflections` for associations (`has_many`, `belongs_to`, `has_one`, `has_and_belongs_to_many`), including `:through`, `:polymorphic`, `:class_name` overrides.
2. **`ActiveRecord::Base.connection.columns(table)`** — column names, types, defaults, nullability.
3. **`db/schema.rb` or `db/structure.sql` parsing** — fallback for index definitions, foreign keys, and tables without a model.
4. **Validators** (optional) — `Model.validators` for presence, uniqueness, length constraints.

### 3.2 Model Discovery

```ruby
module SchemaVision
  module Extractor
    class ModelScanner
      def discover_models
        Rails.application.eager_load! # Ensure all models are loaded
        ActiveRecord::Base.descendants
          .reject(&:abstract_class?)
          .reject { |m| m.name.nil? } # anonymous classes
          .select { |m| m.table_exists? }
      end
    end
  end
end
```

**STI handling:** Models sharing a table are grouped. The parent is the primary node; children appear as badges/tags on that node.

**Polymorphic handling:** Polymorphic associations are rendered as dashed edges fanning out to all concrete types.

### 3.3 Intermediate Data Format (JSON Graph)

```json
{
  "nodes": [
    {
      "id": "User",
      "table": "users",
      "columns": [
        { "name": "id", "type": "bigint", "primary": true },
        { "name": "email", "type": "string", "nullable": false, "index": "unique" },
        { "name": "name", "type": "string", "nullable": true }
      ],
      "sti_children": ["AdminUser", "GuestUser"],
      "validations": ["email: presence, uniqueness"],
      "namespace": "app/models",
      "concerns": ["Authenticatable", "Trackable"]
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
    "model_count": 42,
    "adapter": "postgresql"
  }
}
```

---

## 4. Interactive Frontend Design

The generated HTML file is a **single self-contained file** — no CDN dependencies, no network requests. All JS and CSS are inlined. The JSON graph is embedded as a `<script>` tag.

### 4.1 Technology Choices

| Concern | Choice | Rationale |
|---|---|---|
| Graph rendering | **Canvas (custom)** or **SVG + d3-force** (bundled/minified) | SVG gives DOM-level interactivity; Canvas scales for 500+ models |
| Layout algorithm | Force-directed (d3-force) with constraint layers | Natural clustering of related models |
| UI framework | Vanilla JS (no framework) | Zero dependencies, small file size |
| Styling | CSS custom properties + embedded stylesheet | Theming support, dark/light mode |

### 4.2 Core Interactive Features

#### A. Model Selector Panel (left sidebar)

- **Searchable list** of all models with fuzzy matching
- **Namespace grouping** — collapsible tree (`Admin::`, `Billing::`, etc.)
- **Multi-select checkboxes** — toggle which models are visible on the canvas
- **Quick filters**: "Show all", "Clear all", "Only models with associations to [X]"
- **Tag filters**: filter by concern, namespace, or custom tags

#### B. Canvas / Diagram Area (center)

- **Nodes** = model cards showing:
  - Model name (bold header)
  - Column list (expandable/collapsible — collapsed by default for large schemas)
  - Primary key highlighted, foreign keys with a link icon
  - Colored badges for STI children, concerns
  - Column types shown in a muted typeface
- **Edges** = association lines:
  - Solid lines: `belongs_to` / `has_one` / `has_many`
  - Dashed lines: `has_many :through`
  - Dotted lines: polymorphic associations
  - Arrow markers indicate cardinality (→ one, →→ many)
  - Labels on hover (association name + foreign key)
- **Force-directed layout** that stabilizes, then allows manual drag-and-drop repositioning
- **Cluster gravity** — models sharing a namespace or heavy association overlap are pulled together

#### C. Zoom & Navigation

- **Scroll-wheel zoom** with smooth interpolation
- **Pinch-to-zoom** on trackpads
- **Minimap** (bottom-right corner) — a thumbnail of the full graph with a viewport rectangle you can drag
- **Fit-to-screen** button — auto-zooms to show all visible nodes
- **Zoom-to-selection** — double-click a model in the sidebar to center + zoom to it
- **Zoom level indicator** — percentage display, click to reset to 100%

#### D. Focus Mode ("Spotlight")

When a user clicks on a model node:

1. The selected model and its **directly associated models** are highlighted
2. All other nodes and edges fade to 20% opacity
3. A **detail panel** (right sidebar) slides in showing:
   - Full column list with types, constraints, defaults
   - All associations (grouped: `belongs_to`, `has_many`, `has_one`)
   - Validations
   - Indices
   - STI hierarchy if applicable
4. **Depth slider** (1–3 hops) — expand the spotlight radius to show 2nd and 3rd-degree associations
5. Click canvas background or press `Esc` to exit focus mode

#### E. Layout Modes

Users can switch between layout strategies:

| Mode | Description |
|---|---|
| **Force** (default) | d3-force simulation, organic clustering |
| **Hierarchical** | Top-down tree rooted at a chosen model |
| **Circular** | Models arranged in a circle, edges cross the center |
| **Grid** | Alphabetical or namespace-grouped grid, clean rows/columns |
| **Manual** | Drag nodes freely, positions are persisted to localStorage |

#### F. Additional Features

- **Dark / Light theme toggle** — CSS custom property switch, respects `prefers-color-scheme`
- **Export options**:
  - **PNG** — canvas screenshot via `html2canvas` or native Canvas `toDataURL`
  - **SVG** — if using SVG renderer
  - **JSON** — raw graph data for further processing
  - **Mermaid** — generate a Mermaid ER diagram definition
- **Permalink / State URL** — selected models + zoom + position encoded into a URL hash so you can share a specific view
- **Keyboard shortcuts**: `/` to focus search, `Esc` to deselect, `+`/`-` to zoom, `F` to fit
- **Column diff overlay** (bonus) — if the gem detects a `db/schema.rb` in git history, highlight recently added/removed columns in green/red

---

## 5. Configuration

```ruby
# config/initializers/schema_vision.rb
SchemaVision.configure do |config|
  # Output
  config.output_path = "docs/schema.html"

  # Filtering
  config.exclude_models = ["ActiveStorage::Blob", "ActionMailbox::*"]
  config.include_only   = nil  # nil = all, or explicit list
  config.show_sti       = true
  config.show_concerns  = true
  config.show_validations = true

  # Appearance
  config.title          = "MyApp Schema"
  config.theme          = :auto  # :light, :dark, :auto
  config.default_layout = :force # :force, :hierarchical, :circular, :grid
  config.expand_columns = false  # start with columns collapsed

  # Graph tuning
  config.max_depth      = 3     # max association hops in focus mode
  config.cluster_by     = :namespace  # :namespace, :concern, :none

  # Advanced
  config.custom_css     = nil   # path to a CSS file to inline
  config.custom_js      = nil   # path to a JS file to inline
  config.schema_path    = nil   # override schema.rb location
end
```

---

## 6. Gem Structure

```
schema_vision/
├── lib/
│   ├── schema_vision.rb              # Entry point, configuration DSL
│   ├── schema_vision/
│   │   ├── version.rb
│   │   ├── configuration.rb           # Config object
│   │   ├── railtie.rb                 # Rails integration, rake tasks
│   │   ├── cli.rb                     # Thor-based CLI
│   │   ├── extractor/
│   │   │   ├── model_scanner.rb       # Discovers AR models
│   │   │   ├── association_reader.rb  # Reads reflections
│   │   │   ├── column_reader.rb       # Reads columns, indices
│   │   │   ├── validation_reader.rb   # Reads validators
│   │   │   └── schema_parser.rb       # Parses schema.rb fallback
│   │   ├── transformer/
│   │   │   ├── graph_builder.rb       # Builds node/edge graph
│   │   │   ├── node.rb                # Value object
│   │   │   ├── edge.rb                # Value object
│   │   │   └── filters.rb            # Applies exclude/include rules
│   │   ├── renderer/
│   │   │   ├── html_generator.rb      # ERB rendering, asset inlining
│   │   │   └── exporters/
│   │   │       ├── mermaid.rb         # Mermaid ER export
│   │   │       └── json.rb            # Raw JSON export
│   │   └── assets/
│   │       ├── template.html.erb      # Main HTML template
│   │       ├── app.js                 # Interactive frontend (ES6, bundled)
│   │       ├── style.css              # Stylesheet
│   │       └── vendor/
│   │           └── d3-force.min.js    # Vendored d3-force (if used)
│   └── generators/
│       └── schema_vision/
│           └── install_generator.rb   # rails generate schema_vision:install
├── exe/
│   └── schema_vision                  # CLI binary
├── spec/
│   ├── extractor/
│   ├── transformer/
│   ├── renderer/
│   └── integration/
├── Gemfile
├── schema_vision.gemspec
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

The gem could optionally provide a mounted engine for live-reloading during development (future enhancement), but the primary output is always a static file.

### Why force-directed layout?

It handles unknown schemas gracefully — you don't need to pre-define positions. Combined with namespace clustering and manual override, it gives the best default experience.

---

## 8. Performance Considerations

| Scale | Strategy |
|---|---|
| < 50 models | Full SVG rendering, all features enabled |
| 50–200 models | SVG with virtualized rendering (only render visible viewport nodes) |
| 200–500 models | Switch to Canvas renderer automatically |
| 500+ models | Canvas + aggressive clustering (collapse namespaces into single super-nodes) |

The extractor runs at boot via `eager_load!`. For large apps, extraction typically takes < 2 seconds. HTML generation is fast since it's just ERB + JSON serialization.

---

## 9. Testing Strategy

| Layer | Approach |
|---|---|
| Extractor | Unit tests with a fake Rails app (using `combustion` gem or inline AR model definitions) |
| Transformer | Pure Ruby unit tests — graph building, filtering, edge deduplication |
| Renderer | Snapshot tests — compare generated HTML structure against fixtures |
| Frontend JS | Headless browser tests (Playwright or Puppeteer) for interactivity |
| Integration | End-to-end: generate HTML from a sample Rails app, open in headless browser, assert nodes/edges are rendered |

---

## 10. Future Enhancements (Roadmap)

1. **Live mode** — a mounted Rails engine with ActionCable that hot-reloads when migrations run
2. **Annotation integration** — read `annotate` gem comments for human-readable column descriptions
3. **Schema diff** — compare two generated JSONs and highlight additions/removals/changes
4. **Multi-database support** — Rails 6+ multi-DB configs, render each database as a separate cluster
5. **ER diagram standards** — toggle between crow's foot, UML, and simple line notation
6. **Collaboration** — export positions/layout as a `.schema_vision.json` config that can be committed and shared across team members
7. **Plugin system** — allow custom extractors (e.g., for Mongoid, Sequel) and custom renderers

---

## 11. Dependencies

```ruby
# schema_vision.gemspec
Gem::Specification.new do |spec|
  spec.name    = "schema_vision"
  spec.version = SchemaVision::VERSION

  spec.add_dependency "railties", ">= 6.0"
  spec.add_dependency "activerecord", ">= 6.0"
  spec.add_dependency "thor", "~> 1.0"        # CLI

  spec.add_development_dependency "rspec"
  spec.add_development_dependency "combustion"  # In-memory Rails app for tests
  spec.add_development_dependency "capybara"
  spec.add_development_dependency "playwright-ruby-client"
end
```

**Zero runtime JS dependencies shipped to the user** — d3-force (or equivalent) is vendored and minified into the template. The HTML file has no external requests.

---

*Generated for discussion purposes. Implementation details subject to refinement during development.*
