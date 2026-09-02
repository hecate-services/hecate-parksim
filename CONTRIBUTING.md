# Contributing

Trunk-based. Commit directly to `main`. No PRs, no feature branches.

## Build

```bash
rebar3 compile
rebar3 ct
```

## Style

- Erlang: `warnings_as_errors`, dialyzer clean
- Vertical slicing only — `apps/<cmd-app>/src/<slice>/{cmd, event, handler, api}.erl`

## Regenerate slices

```bash
python3 scripts/scaffold-slices.py
```

## Issues

https://github.com/hecate-services/hecate-parksim-entry2exit/issues
