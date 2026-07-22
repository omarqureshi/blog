# frozen_string_literal: true

# Ruby side of the synth benchmark. Mirror of ../python/app.py — keep in sync.
require "json"

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
require "aws-cdk-lib"
t1 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

app = AWSCDK::App.new({ outdir: ENV.fetch("BENCH_OUTDIR", "cdk.out") })
stack = AWSCDK::Stack.new(app, "BenchStack")

vpc = AWSCDK::EC2::VPC.new(stack, "Vpc", { max_azs: 2, nat_gateways: 1 })

buckets = (0...25).map do |i|
  AWSCDK::S3::Bucket.new(stack, "Bucket#{i}", { versioned: true })
end

table = AWSCDK::DynamoDB::TableV2.new(
  stack,
  "Table",
  { partition_key: { name: "id", type: AWSCDK::DynamoDB::AttributeType::STRING } }
)

queue = AWSCDK::SQS::Queue.new(stack, "Queue")
topic = AWSCDK::SNS::Topic.new(stack, "Topic")

fn = AWSCDK::Lambda::Function.new(
  stack,
  "Fn",
  {
    runtime: AWSCDK::Lambda::Runtime.PYTHON_3_12,
    handler: "index.handler",
    code: AWSCDK::Lambda::Code.from_inline("def handler(event, context):\n    return {}")
  }
)

table.grant_read_write_data(fn)
buckets[0].grant_read(fn)
queue.grant_send_messages(fn)

api = AWSCDK::APIGateway::LambdaRestAPI.new(stack, "Api", { handler: fn })

AWSCDK::CfnOutput.new(stack, "ApiUrl", { value: api.url })

t2 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
app.synth
t3 = Process.clock_gettime(Process::CLOCK_MONOTONIC)

warn JSON.generate({ import_s: t1 - t0, construct_s: t2 - t1, synth_s: t3 - t2, total_s: t3 - t0 })
