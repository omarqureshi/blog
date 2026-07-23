# Python vs Ruby CDK synth benchmark

Evidence for the performance FAQ in the Ruby bindings RFC
([aws/aws-cdk-rfcs#939](https://github.com/aws/aws-cdk-rfcs/pull/939)).
Both languages are jsii guests (Node kernel sidecar) running the identical
stack — `python/app.py` and `ruby/app.rb` are kept in mirror: a VPC, 25
versioned S3 buckets, a DynamoDB TableV2, SQS queue, SNS topic, an inline
Lambda with three IAM grants, and a LambdaRestAPI. Both synthesize the same
64-resource template (asserted per run).

```sh
./run.sh          # 5 measured iterations + 1 discarded warmup per language
```

Measures full-process wall time (the `cdk synth` UX), peak RSS via GNU time,
and each app's in-process phase breakdown (library load / construct / synth)
printed on stderr.

## Results — 2026-07-23

Host: WSL2, Ruby 4.0.5, Python 3.12.3, Node 24.15.0.
Python `aws-cdk-lib` 2.261.0 (PyPI); Ruby `aws-cdk-lib` 0.0.0.pre.20260722115628
(preview feed; built from the fork of aws-cdk main — version skew is disclosed,
not hidden). Medians of 5; memory is `/proc` VmHWM self-reported by each app
(guest process + Node sidecar):

| | Python | Ruby |
| --- | --- | --- |
| total wall | 1.55 s | 2.28 s |
| library load | 0.98 s | 0.46 s |
| construct | 0.26 s | 0.30 s |
| synth | 0.09 s | 1.15 s |
| guest process peak | 128 MB | 86 MB |
| Node sidecar peak | 47 MB | 56 MB |
| process-tree peak | 175 MB | 142 MB |

Reading: end-to-end synth UX is comparable (~0.7s slower on this stack).
Ruby's lazy-loading architecture makes `require "aws-cdk-lib"` ~2× faster
than Python's imports **and** the guest process a third smaller (only the
generated files a program touches are ever loaded — 67 of 613 module files in
this run).

## Where the synth gap comes from (profiled 2026-07-23)

The 1.15s-vs-0.09s synth row is **not a Ruby or jsii cost — it is version
skew in aws-cdk-lib itself.** The Ruby preview gem is built from `aws-cdk`
`main`, where `app.synth()` now always runs the default CloudFormation
validation engine (`@aws/cloudformation-validate` — a WebAssembly-compiled
Rego policy engine, `core/lib/validation/cloudformation-validate-plugin.js`).
Python's 2.261.0 PyPI release predates the feature.

Evidence chain:

1. A V8 CPU profile of the Node sidecar during the Ruby synth showed ~50%
   anonymous WASM frames + ~20% GC; walking the call tree resolved the WASM
   caller to `WasmRegoEngine` → `CloudFormationValidatePlugin` →
   `synthesis-validation.js` inside `app.synth()`.
2. A pure-Node control (identical one-bucket app in plain JavaScript, no
   jsii guest at all, both libraries loaded from the jsii package cache with
   their dependency closures) reproduces the entire gap:

   | | preview build (main) | release 2.261.0 |
   | --- | --- | --- |
   | require | 7 ms | 6 ms |
   | construct | ~100 ms | ~100 ms |
   | **synth** | **~1,100 ms** | **~28 ms** |

3. Splitting the cost on the preview build: engine initialisation (WASM
   compile + rule load) ≈ 0.6s, template evaluation ≈ 0.6s — and the cost is
   near-fixed (a 1-bucket app pays ~1.1s, the 64-resource app ~1.15s).
4. Net jsii overhead in the synth phase after subtracting the library's own
   cost: Ruby ≈ 0.1s, Python ≈ 0.06s — equivalent. The kernel wire trace
   agrees: synth is a single `invoke`, with 0.001s of Ruby-side CPU.

When the upstream feature reaches a tagged release, the Python column will
pay the same ~1.1s and the synth rows will converge.

**Measurement post-mortem (2026-07-23):** an earlier revision reported Ruby at
478 MB peak RSS via GNU time `%M`. That number was a WSL2 accounting artifact:
in the same run, `%M` claimed 486 MB while concurrent `/proc` sampling showed
the Ruby process peaking at 86 MB (the `bash -c` + `bundle exec` re-exec chain
triggers the bug; the bare python invocation did not, which manufactured a
phantom asymmetry). The same broken accounting produces occasional negative
`%e` wall times. The harness now ignores `%M` entirely — each app self-reports
`/proc` VmHWM for itself and its sidecar.
