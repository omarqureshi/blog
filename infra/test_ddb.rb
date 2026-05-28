require 'aws-sdk-dynamodb'
client = Aws::DynamoDB::Client.new(region: 'us-east-1', stub_responses: true)
begin
  client.put_item({
    table_name: 'test',
    item: { 'pk' => 'val' }
  })
  puts "put_item works"
rescue => e
  puts "put_item error: #{e.class} - #{e.message}"
end

begin
  client.query({
    table_name: 'test',
    key_condition_expression: "pk = :pk",
    expression_attribute_values: {
      ":pk" => "PAGEVIEW"
    }
  })
  puts "query works"
rescue => e
  puts "query error: #{e.class} - #{e.message}"
end
