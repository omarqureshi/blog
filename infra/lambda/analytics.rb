require 'json'
require 'aws-sdk-athena'
require 'aws-sdk-s3'
require 'time'

def handler(event:, context:)
  athena = Aws::Athena::Client.new
  s3 = Aws::S3::Client.new

  cache_bucket = ENV['CACHE_BUCKET']
  cache_key = ENV['CACHE_KEY']
  athena_output_bucket = ENV['ATHENA_OUTPUT_BUCKET']
  athena_database = ENV['ATHENA_DATABASE']

  # 1. Check Cache
  begin
    cache_obj = s3.get_object(bucket: cache_bucket, key: cache_key)
    last_modified = cache_obj.last_modified
    age_in_minutes = (Time.now.utc - last_modified) / 60.0

    if age_in_minutes < 60
      return {
        statusCode: 200,
        headers: { "Access-Control-Allow-Origin" => "*", "Content-Type" => "application/json" },
        body: cache_obj.body.read
      }
    end
  rescue Aws::S3::Errors::NoSuchKey
    # Cache miss
    puts "Cache miss or stale"
  rescue StandardError => e
    puts "Cache error: #{e.message}"
  end

  # 2. Start Athena Query
  query_str = <<~SQL
    SELECT cs_uri_stem, count(*) as views 
    FROM cloudfront_logs 
    WHERE sc_status = 200 AND cs_uri_stem LIKE '/%' AND cs_uri_stem NOT LIKE '/_astro/%'
    GROUP BY cs_uri_stem 
    ORDER BY views DESC 
    LIMIT 10
  SQL

  start_res = athena.start_query_execution({
    query_string: query_str,
    query_execution_context: { database: athena_database },
    result_configuration: { output_location: athena_output_bucket }
  })

  execution_id = start_res.query_execution_id

  # 3. Poll for completion
  status = 'RUNNING'
  while ['RUNNING', 'QUEUED'].include?(status)
    sleep(1)
    status_res = athena.get_query_execution({ query_execution_id: execution_id })
    status = status_res.query_execution.status.state
    if ['FAILED', 'CANCELLED'].include?(status)
      raise "Athena query failed: #{status_res.query_execution.status.state_change_reason}"
    end
  end

  # 4. Fetch Results
  results_res = athena.get_query_results({ query_execution_id: execution_id })
  
  # Parse Athena Results (skip header row)
  rows = results_res.result_set.rows[1..] || []
  data = rows.map do |row|
    {
      path: row.data[0].var_char_value,
      views: row.data[1].var_char_value.to_i
    }
  end

  response_body = data.to_json

  # 5. Update Cache
  s3.put_object({
    bucket: cache_bucket,
    key: cache_key,
    body: response_body,
    content_type: "application/json"
  })

  {
    statusCode: 200,
    headers: { "Access-Control-Allow-Origin" => "*", "Content-Type" => "application/json" },
    body: response_body
  }
rescue StandardError => e
  puts "Error: #{e.message}"
  {
    statusCode: 500,
    headers: { "Access-Control-Allow-Origin" => "*" },
    body: { error: e.message }.to_json
  }
end
