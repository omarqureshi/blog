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

## Results — 2026-07-22

Host: WSL2, Ruby 4.0.5, Python 3.12.3, Node 24.15.0.
Python `aws-cdk-lib` 2.261.0 (PyPI); Ruby `aws-cdk-lib` 0.0.0.pre.20260722115628
(preview feed; built from the fork of aws-cdk main — version skew is disclosed,
not hidden). Medians of 5:

| | Python | Ruby |
| --- | --- | --- |
| total wall | 2.05 s | 2.40 s |
| library load | 1.24 s | 0.49 s |
| construct | 0.29 s | 0.31 s |
| synth | 0.09 s | 1.15 s |
| peak RSS | 130 MB | 478 MB |

Reading: end-to-end synth UX is comparable (~17% slower). Ruby's lazy-loading
architecture makes `require "aws-cdk-lib"` ~2.5× faster than Python's imports;
the cost moves to the synth phase, where lazily-referenced types hydrate
through the kernel. Peak memory is the honest gap and the first optimisation
target.

Known harness quirk: GNU time occasionally reports a negative `%e` on WSL2;
medians of 5 absorb it, but treat single runs with suspicion.
