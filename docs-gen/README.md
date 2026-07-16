# docs-gen — Ruby CDK API docs

Generates the `aws-cdk-lib` Ruby API reference served at
`https://rubygems.omarqureshi.net/docs`. Driven by `.github/workflows/publish-docs.yml`.

> **Home is temporary.** These scripts live here because the publish pipeline does, but
> they belong in [jsii-rosetta](https://github.com/omarqureshi/jsii-rosetta) (the
> doc/example toolchain). They're self-contained to make that move easy.

## Why one unified YARD run

`aws-cdk-lib` is ~11,400 generated Ruby files across ~324 modules. It's built in a
**single `yard doc` run** so cross-module type links resolve — YARD only linkifies types
present in its registry at render time, so S3's `encryption_key : KMS::IKey` only becomes
a link to `AWSCDK/KMS/IKey.html` if KMS is in the *same* run. Per-module builds leave
every such reference as plain text.

YARD's registry resolver stack-overflows on deep recursion (the old blocker that forced
per-module builds); `build-module-docs.sh` raises the C stack with `ulimit -s`, so the
whole library builds in one pass. Measured: ~46 min, ~8.3 GB peak RSS, ~20k pages — well
within a GitHub runner. YARD's monolithic `class_list.html`/search index is generated but
harmless: the theme hides the frame nav and we ship our own assembly-driven index.

Set `PER_MODULE=1` to fall back to isolated per-module builds (crash-safe, but
cross-module links won't resolve) — a safety valve, not the default.

## Pipeline (run in order)

| step | script | does |
|------|--------|------|
| 1 | `build-module-docs.sh <gem-lib> <out> [modules…]` | one unified YARD run (all modules, one registry → cross-module links); applies `docs-theme.css` |
| 2 | `gen-module-landing.rb <assembly> <out>` | a landing per submodule (incl. nested namespaces like `ECR/Mixins`) — classes/interfaces/enums + child namespaces |
| 3 | `inject-crumb.rb <out>` | full-path breadcrumb into each class page (runs *after* landings so it can tell namespaces from classes); the theme hides YARD's broken frame nav |
| 4 | `gen-index.rb <assembly> <out>` | `AWSCDK/index.html` (top-level modules only) + `/` → `/AWSCDK/` redirect |

- **YARD** renders the class pages (with Ruby `@example` blocks from jsii-rosetta).
- The **jsii assembly** (`.jsii`) drives the module list, names, and per-class kind/summary.
- All links are **relative** → the built site is mount-agnostic (works at `/docs`, `/`, anywhere).

## Local preview

Serve the built `out/` under a mount prefix to mimic the deploy:
`DOCS_MOUNT=docs DOCS_ROOT=./out PORT=8001 python3 serve-docs.py` (dev-only; not in the repo).
