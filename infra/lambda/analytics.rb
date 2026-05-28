# frozen_string_literal: true

require 'json'
require 'aws-sdk-dynamodb'
require 'time'
require 'securerandom'
require 'digest'

def handler(event:, context:)
  dynamodb = Aws::DynamoDB::Client.new
  table_name = ENV['TABLE_NAME']

  method = event['httpMethod']
  path = event['resource']

  # Enable CORS for responses
  headers = {
    'Access-Control-Allow-Origin' => '*',
    'Content-Type' => 'application/json'
  }

  if method == 'POST' && path == '/api/track'
    handle_track(event, dynamodb, table_name, headers)
  elsif method == 'GET' && path == '/api/analytics'
    handle_analytics(event, dynamodb, table_name, headers)
  else
    { statusCode: 404, headers: headers, body: 'Not Found' }
  end
rescue StandardError => e
  puts "Error: #{e.message}"
  puts e.backtrace.join("\n")
  { statusCode: 500, headers: headers, body: { error: 'Internal Server Error' }.to_json }
end

def handle_track(event, dynamodb, table_name, headers)
  body = JSON.parse(event['body'] || '{}')
  req_headers = event['headers'] || {}

  # Extract Data
  path = body['path'] || '/'
  referrer = body['referrer'] || 'direct'
  user_agent = body['userAgent'] || req_headers['User-Agent'] || 'unknown'

  # CloudFront Geolocation Headers
  country = req_headers['CloudFront-Viewer-Country'] || req_headers['cloudfront-viewer-country'] || 'Unknown'
  city = req_headers['CloudFront-Viewer-City'] || req_headers['cloudfront-viewer-city'] || 'Unknown'

  # IP from API Gateway
  ip = event.dig('requestContext', 'identity', 'sourceIp') || '0.0.0.0'

  # Cookieless Tracking: Hash IP + UserAgent + Date
  date_str = Time.now.utc.strftime('%Y-%m-%d')
  visitor_id = Digest::SHA256.hexdigest("#{ip}-#{user_agent}-#{date_str}")[0..15]

  timestamp = Time.now.utc.iso8601

  item = {
    'pk' => "PAGEVIEW##{date_str}",
    'sk' => "#{timestamp}##{SecureRandom.uuid}",
    'path' => path,
    'referrer' => referrer,
    'country' => country,
    'city' => city,
    'visitor_id' => visitor_id
  }

  dynamodb.put_item({
                      table_name: table_name,
                      item: item
                    })

  { statusCode: 200, headers: headers, body: { success: true }.to_json }
end

def handle_analytics(_event, dynamodb, table_name, headers)
  # Query the last 7 days of data (for simplicity)
  today = Time.now.utc
  dates = (0..6).map { |i| (today - (i * 86_400)).strftime('%Y-%m-%d') }

  all_items = []

  dates.each do |date_str|
    res = dynamodb.query({
                           table_name: table_name,
                           key_condition_expression: 'pk = :pk',
                           expression_attribute_values: {
                             ':pk' => "PAGEVIEW##{date_str}"
                           }
                         })
    all_items.concat(res.items)
  end

  # Aggregations
  total_views = all_items.size
  unique_visitors = all_items.map { |i| i['visitor_id'] }.uniq.size

  # Top Pages
  paths = all_items.map { |i| i['path'] }.tally
  top_pages = paths.sort_by { |_, count| -count }.take(10).map { |p, c| { path: p, views: c } }

  # Top Referrers
  referrers = all_items.map { |i| i['referrer'] }.tally
  top_referrers = referrers.sort_by { |_, count| -count }.take(10).map { |r, c| { referrer: r, views: c } }

  # Top Countries
  countries = all_items.map { |i| i['country'] }.tally
  top_countries = countries.sort_by { |_, count| -count }.take(10).map { |c, count| { country: c, views: count } }

  response_data = {
    total_views: total_views,
    unique_visitors: unique_visitors,
    top_pages: top_pages,
    top_referrers: top_referrers,
    top_countries: top_countries
  }

  { statusCode: 200, headers: headers, body: response_data.to_json }
end
