# frozen_string_literal: true

require 'json'
require 'aws-sdk-dynamodb'
require 'time'
require 'securerandom'
require 'digest'

HEADERS = {
  'Access-Control-Allow-Origin' => '*',
  'Content-Type' => 'application/json'
}.freeze!

TABLE_NAME = ENV['TABLE_NAME'].freeze!

# Disable UnusedMethodArgument for context variable
# rubocop:disable Lint/UnusedMethodArgument

# Main handler for Lambda function
def handler(event:, context:)
  handle_request(event)
rescue StandardError => e
  puts "Error: #{e.message}"
  puts e.backtrace.join("\n")
  { statusCode: 500, headers: HEADERS, body: { error: 'Internal Server Error' }.to_json }
end
# rubocop:enable Lint/UnusedMethodArgument

def handle_request(event)
  method = event['httpMethod']
  path = event['resource']
  # Enable CORS for responses
  if method == 'POST' && path == '/api/track'
    handle_track(event)
  elsif method == 'GET' && path == '/api/analytics'
    handle_analytics(event)
  else
    { statusCode: 404, headers: HEADERS, body: 'Not Found' }
  end
end

def handle_track(event)
  body = JSON.parse(event['body'] || '{}')
  req_headers = event['headers'] || {}

  # Extract Data
  body_attributes = extract_body_attributes(body)

  # CloudFront Geolocation Headers
  req_headers_attributes = extract_req_headers_attributes(req_headers)

  # Cookieless Tracking: Hash IP + UserAgent + Date
  date_str = Time.now.utc.strftime('%Y-%m-%d')

  item = build_tracking_item(date_str, body_attributes, req_headers_attributes)
  save_tracking(item)

  { statusCode: 200, headers: HEADERS, body: { success: true }.to_json }
end

def build_visitor_id(date_str, body_attributes)
  # IP from API Gateway
  ip = event.dig('requestContext', 'identity', 'sourceIp') || '0.0.0.0'
  # Cookieless Tracking: Hash IP + UserAgent + Date
  Digest::SHA256.hexdigest("#{ip}-#{body_attributes[:user_agent]}-#{date_str}")[0..15]
end

def extract_body_attributes(body)
  returning = {}
  returning[:path] = body['path'] || '/'
  returning[:referrer] = body['referrer'] || 'direct'
  returning[:user_agent] = body['userAgent'] || req_headers['User-Agent'] || 'unknown'
  returning
end

def extract_req_headers_attributes(req_headers)
  returning = {}
  returning[:country] = req_headers['CloudFront-Viewer-Country'] || req_headers['cloudfront-viewer-country'] ||
                        'Unknown'
  returning[:city] = req_headers['CloudFront-Viewer-City'] || req_headers['cloudfront-viewer-city'] || 'Unknown'
  returning
end

def save_tracking(item)
  dynamodb_client.put_item(
    {
      table_name: TABLE_NAME,
      item: item
    }
  )
end

def build_tracking_item(date_str, body_attributes, req_headers_attributes)
  visitor_id = build_visitor_id(date_str, body_attributes)
  {
    'pk' => "PAGEVIEW##{date_str}",
    'sk' => "#{Time.now.utc.iso8601}##{SecureRandom.uuid}",
    'path' => body_attributes[:path],
    'referrer' => body_attributes[:referrer],
    'country' => req_headers_attributes[:country],
    'city' => req_headers_attributes[:city],
    'visitor_id' => visitor_id
  }
end

def handle_analytics(_event)
  # Query the last 7 days of data (for simplicity)
  today = Time.now.utc
  dates = (0..6).map { |i| (today - (i * 86_400)).strftime('%Y-%m-%d') }

  all_items = []

  dates.each do |date_str|
    res = analytics_query(date_str)
    all_items.concat(res.items)
  end
  { statusCode: 200, headers: HEADERS, body: build_aggregations(all_items).to_json }
end

def analytics_query(date_str)
  dynamodb_client.query({
                          table_name: TABLE_NAME,
                          key_condition_expression: 'pk = :pk',
                          expression_attribute_values: {
                            ':pk' => "PAGEVIEW##{date_str}"
                          }
                        })
end

def build_aggregations(all_items)
  returning = {}
  returning[:total_views] = all_items.size
  returning[:unique_visitors] = all_items.map { |i| i['visitor_id'] }.uniq.size
  returning[:top_pages] = top_ten(all_items, 'path')
  returning[:top_referrers] = top_ten(all_items, 'referrer')
  returning[:top_countries] = top_ten(all_items, 'country')
  returning
end

def top_ten(collection, key)
  tallied = collection.map { |i| i[key] }.tally
  tallied.sort_by { |_, count| -count }.take(10).map do |p, c|
    {
      key.to_sym => p,
      :views => c
    }
  end
end

def dynamodb_client
  Aws::DynamoDB::Client.new
end
