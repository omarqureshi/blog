"""Python side of the synth benchmark. Mirror of ../ruby/app.rb — keep in sync."""
import json
import os
import sys
import time

t0 = time.perf_counter()
import aws_cdk as cdk
from aws_cdk import (
    aws_apigateway as apigw,
    aws_dynamodb as ddb,
    aws_ec2 as ec2,
    aws_lambda as lambda_,
    aws_s3 as s3,
    aws_sns as sns,
    aws_sqs as sqs,
)
t1 = time.perf_counter()

app = cdk.App(outdir=os.environ.get("BENCH_OUTDIR", "cdk.out"))
stack = cdk.Stack(app, "BenchStack")

vpc = ec2.Vpc(stack, "Vpc", max_azs=2, nat_gateways=1)

buckets = [
    s3.Bucket(stack, f"Bucket{i}", versioned=True)
    for i in range(25)
]

table = ddb.TableV2(
    stack,
    "Table",
    partition_key=ddb.Attribute(name="id", type=ddb.AttributeType.STRING),
)

queue = sqs.Queue(stack, "Queue")
topic = sns.Topic(stack, "Topic")

fn = lambda_.Function(
    stack,
    "Fn",
    runtime=lambda_.Runtime.PYTHON_3_12,
    handler="index.handler",
    code=lambda_.Code.from_inline("def handler(event, context):\n    return {}"),
)

table.grant_read_write_data(fn)
buckets[0].grant_read(fn)
queue.grant_send_messages(fn)

api = apigw.LambdaRestApi(stack, "Api", handler=fn)

cdk.CfnOutput(stack, "ApiUrl", value=api.url)

t2 = time.perf_counter()
app.synth()
t3 = time.perf_counter()

def _hwm_mb(pid):
    try:
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("VmHWM"):
                    return int(line.split()[1]) // 1024
    except FileNotFoundError:
        return None

def _children(pid):
    kids = []
    for t in os.listdir(f"/proc/{pid}/task"):
        with open(f"/proc/{pid}/task/{t}/children") as f:
            kids += [int(x) for x in f.read().split()]
    return kids

_kids = _children(os.getpid())
json.dump(
    {"import_s": t1 - t0, "construct_s": t2 - t1, "synth_s": t3 - t2, "total_s": t3 - t0,
     "guest_hwm_mb": _hwm_mb(os.getpid()),
     "sidecar_hwm_mb": max((_hwm_mb(k) or 0) for k in _kids) if _kids else None},
    sys.stderr,
)
sys.stderr.write("\n")
