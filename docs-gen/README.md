# docs-gen — Ruby CDK API docs

Generates the `aws-cdk-lib` Ruby API reference served at
`https://rubygems.omarqureshi.net/docs`. Driven by `.github/workflows/publish-docs.yml`.

> **Home is temporary.** These scripts live here because the publish pipeline does, but
> they belong in [jsii-rosetta](https://github.com/omarqureshi/jsii-rosetta) (the
> doc/example toolchain). They're self-contained to make that move easy.

## Why per-module

`aws-cdk-lib` is ~11,400 generated Ruby files across ~327 modules — too large for a
single YARD run (its registry resolver stack-overflows at ~750 files, and the monolithic
index would be tens of MB). So each module is built in isolation and merged into one
`AWSCDK/<Module>/` tree, with the top-level index driven by the jsii **assembly**.

## Pipeline (run in order)

| step | script | does |
|------|--------|------|
| 1 | `build-module-docs.sh <gem-lib> <out> [modules…]` | per-module YARD, merged; applies `docs-theme.css` |
| 2 | `gen-module-landing.rb <assembly> <out>` | a landing per submodule (incl. nested namespaces like `ECR/Mixins`) — classes/interfaces/enums + child namespaces |
| 3 | `inject-crumb.rb <out>` | full-path breadcrumb into each class page (runs *after* landings so it can tell namespaces from classes); the theme hides YARD's broken frame nav |
| 4 | `gen-index.rb <assembly> <out>` | `AWSCDK/index.html` (top-level modules only) + `/` → `/AWSCDK/` redirect |

- **YARD** renders the class pages (with Ruby `@example` blocks from jsii-rosetta).
- The **jsii assembly** (`.jsii`) drives the module list, names, and per-class kind/summary.
- All links are **relative** → the built site is mount-agnostic (works at `/docs`, `/`, anywhere).

## Local preview

Serve the built `out/` under a mount prefix to mimic the deploy:
`DOCS_MOUNT=docs DOCS_ROOT=./out PORT=8001 python3 serve-docs.py` (dev-only; not in the repo).
