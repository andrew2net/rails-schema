# Contributing to Rails::Schema

Thanks for your interest in improving `rails-schema`! Contributions are welcome —
bug reports, feature ideas, documentation fixes, and pull requests are all
appreciated.

## Ways to contribute

- **Report a bug** — open an [issue](https://github.com/andrew2net/rails-schema/issues)
  with steps to reproduce, the Ruby/Rails versions you're using, and a sample of
  the relevant `schema.rb` / `structure.sql` or model code where possible.
- **Propose a feature** — open an issue describing the use case before sending a
  large PR, so we can agree on the approach. Smaller, self-contained PRs are
  easier to review and merge.
- **Send a pull request** — for typos, docs, and small fixes, feel free to open a
  PR directly.

## Development setup

```bash
git clone https://github.com/andrew2net/rails-schema.git
cd rails-schema
bin/setup        # or: bundle install
```

Requirements: Ruby >= 2.7, Rails >= 5.2.

## Before you open a pull request

Run the full test suite and the linter — CI checks both:

```bash
bundle exec rspec          # run all tests
bundle exec rubocop        # run the linter
bundle exec rake           # runs both (what CI runs)
```

Please also:

- Add or update tests for any behavior you change.
- Keep changes focused; one logical change per PR.
- Match the existing code style (double-quoted strings, RuboCop max method
  length of 15 lines — see `.rubocop.yml`).
- Update `README.md` and `CHANGELOG.md` when your change affects users.

## Architecture overview

The gem is a three-layer pipeline: **Extractor → Transformer → Renderer**.

- **Extractor** (`lib/rails/schema/extractor/`) — discovers models and reads
  columns/associations. Schema data comes from parsing `db/schema.rb`
  (`Extractor::SchemaFileParser`) or `db/structure.sql`
  (`Extractor::StructureSqlParser`); the gem does **not** require a live database
  connection.
- **Transformer** (`lib/rails/schema/transformer/`) — normalizes the extracted
  data into a serializable graph of nodes and edges.
- **Renderer** (`lib/rails/schema/renderer/`) — injects the graph into a single
  self-contained HTML/JS/CSS file via ERB.

If you're building a feature that needs schema information, start from the
existing extractors rather than introducing a DB dependency.

## Code of conduct

Be respectful and constructive. Assume good intent.

## License

By contributing, you agree that your contributions will be licensed under the
[MIT License](LICENSE.txt), the same license that covers this project.
