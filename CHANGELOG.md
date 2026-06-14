# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.1.8] - 2026-06-14

### Fixed

- SQLite `structure.sql` parsing — `StructureSqlParser` now correctly extracts all columns from SQLite-format dumps, which place the entire `CREATE TABLE` on a single line. Previously only the primary key was read (every model rendered with just its `id`). Column splitting is now parenthesis- and quote-aware, so commas inside type modifiers (`decimal(5,4)`), `FOREIGN KEY` clauses, and string literals no longer break parsing; inline C-style comments (`/* ... */`) are stripped. PostgreSQL `pg_dump` output continues to parse as before.

## [0.1.7] - 2026-04-25

### Added

- Manual Positioning toggle — toolbar checkbox that removes all simulation forces when enabled; nodes stay wherever they are dropped and drag-and-drop continues to work normally; unchecking re-enables automatic force-directed layout (#33)
- Layout persistence — node positions, visibility, zoom, and toggle states are auto-saved to `localStorage` and restored on page reload; layouts are scoped per schema via a fingerprint hash so different projects don't collide (#33)
- Save/Load Layout — export the current layout as a portable `.json` file to share with teammates or check into git; import a saved layout file to restore it (#33)
- File menu dropdown — toolbar "File" menu groups Export Mermaid, Save Layout, and Load Layout actions (#33)

## [0.1.6] - 2026-03-28

### Added

- Model grouping via `model_schema_group` configuration — organize sidebar models under collapsible group headers with color-coded dots; supports `:namespaces` or a custom `Proc`; same-group nodes cluster via d3 force (#27)
- Packwerk package discovery — `PackwerkDiscovery` auto-discovers model directories from Packwerk packages (`packwerk.yml` → `package_paths`) (#29)
- Through edges toggle — legend checkbox to show/hide `:through` edges at runtime; `show_through_edges` config sets initial state (default `true`); through associations remain visible in the detail panel (#31)

## [0.1.5] - 2026-03-14

### Added

- `exclude_model_if` configuration option: provide a proc/lambda to dynamically exclude models based on arbitrary conditions, works with both ActiveRecord and Mongoid pipelines (#16)
- Mermaid ER diagram export (`.mmd`) — respects sidebar visibility filters so you can export a subset of models (#23)
- Double-click a model node to isolate its neighborhood (#20)
- Shift-click range selection for sidebar checkboxes (#24)
- Smart "Select All" toggle — when all models are selected and a search filter is active, narrows to only filtered models (#24)
- Search clear button in the sidebar (#24)
- Color-coded edge labels by association type (#19)
- Edge deduplication for `has_many`/`belongs_to` pairs — reciprocal associations are merged into a single edge with dual labels, each colored by its own association type

### Changed

- Refactored text measurement and truncation functions for cleaner rendering

## [0.1.4] - 2026-03-08

### Added

- Support for Ruby 2.7+ and Rails 5.2+ (improved compatibility with older versions)

### Changed

- Self-referential-only models (all edges point to themselves) are now placed in a vertical column to the left of the main graph instead of floating in the force simulation
- True orphan models (zero edges) continue to appear in rows above the diagram
- Improved class names and table names visibility

## [0.1.3] - 2026-03-01

### Added

- Mongoid support: visualize MongoDB-backed models without a schema file (`schema_format: :mongoid`)
- Auto-detection of Mongoid when `schema_format: :auto` and `Mongoid::Document` is defined
- Mongoid extractors: `ModelScanner`, `ModelAdapter`, `ColumnReader`, `AssociationReader`
- Support for all Mongoid association types: `has_many`, `has_one`, `belongs_to`, `has_and_belongs_to_many`, `embeds_many`, `embeds_one`, `embedded_in`
- Embedded document styling in the frontend (dashed borders for embed associations)
- Engine model eager-loading for Mongoid apps

## [0.1.2] - 2026-02-22

### Added

- `StructureSqlParser` for extracting schema from `db/structure.sql` files
- `schema_format` configuration option (`:ruby`, `:sql`, `:auto`)
- `warn` messages to all silent rescue blocks in `AssociationReader` and `ColumnReader`

## [0.1.1] - 2026-02-17

### Added

- ERD-style connections with crow's foot notation, directional indicators, and column-level attachment points

### Changed

- Refactored edge routing with cubic Bezier curves and improved self-referential association handling

## [0.1.0] - 2026-02-15

### Added

- Initial release
- Interactive HTML visualization of Rails database schema (force-directed ERD)
- Model introspection: associations, columns, and schema file parsing
- Self-contained single HTML file output (no external dependencies)
- Searchable sidebar, click-to-focus, dark/light theme, keyboard shortcuts
- Rake task (`rails_schema:generate`) and programmatic API
- Configuration DSL: output path, title, theme, expand columns, exclude models
