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
this run); the deferred cost appears in the synth phase, where
lazily-referenced types hydrate through the kernel.

**Measurement post-mortem (2026-07-23):** an earlier revision reported Ruby at
478 MB peak RSS via GNU time `%M`. That number was a WSL2 accounting artifact:
in the same run, `%M` claimed 486 MB while concurrent `/proc` sampling showed
the Ruby process peaking at 86 MB (the `bash -c` + `bundle exec` re-exec chain
triggers the bug; the bare python invocation did not, which manufactured a
phantom asymmetry). The same broken accounting produces occasional negative
`%e` wall times. The harness now ignores `%M` entirely — each app self-reports
`/proc` VmHWM for itself and its sidecar.
