# Contributing

Thanks for helping. Run what CI runs before opening a pull request (Elixir 1.20 or later):

```sh
mix deps.get
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix credo --strict
mix docs --warnings-as-errors
mix deps.unlock --check-unused
mix dialyzer   # informational, not blocking
```

## Tests

- Tests are plain ExUnit on `Ash.DataLayer.Ets` resources in `test/support`. They need no
  database. The tables are private to the test process, so tests run with `async: true` and each
  seeds its own rows.
- Add a test with every behaviour change, and a CHANGELOG line under "Unreleased".
- The package names no domain: test resources are notes, revisions, runs and statuses.

Use short imperative commit subjects ("Report a hidden predecessor as unreadable").
