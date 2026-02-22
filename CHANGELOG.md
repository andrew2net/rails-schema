# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/), and this project adheres to [Semantic Versioning](https://semver.org/).

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
