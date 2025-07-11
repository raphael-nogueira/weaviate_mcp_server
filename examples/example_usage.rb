#!/usr/bin/env ruby

# Example script demonstrating how to interact with the Weaviate MCP Server
# This script shows how to send MCP protocol messages to the server

require 'json'
require 'open3'

class MCPClient
  def initialize(server_command)
    @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(server_command)
  end

  def send_request(request)
    @stdin.puts JSON.generate(request)
    @stdin.flush

    response_line = @stdout.gets
    JSON.parse(response_line) if response_line
  end

  def close
    @stdin.close
    @stdout.close
    @stderr.close
    @wait_thr.value
  end
end

def main
  puts '🚀 Weaviate MCP Server Example Usage'
  puts '=' * 50

  # Start the MCP server
  server_path = File.expand_path('../bin/weaviate-mcp-server', __dir__)
  client = MCPClient.new("ruby #{server_path}")

  begin
    # 1. Initialize the connection
    puts "\n📡 Initializing MCP connection..."
    init_response = client.send_request({
                                          jsonrpc: '2.0',
                                          id: 1,
                                          method: 'initialize',
                                          params: {
                                            protocolVersion: '2024-11-05',
                                            capabilities: {},
                                            clientInfo: {
                                              name: 'example-client',
                                              version: '1.0.0'
                                            }
                                          }
                                        })

    puts '✅ Initialization successful!'
    puts "   Server: #{init_response.dig('result', 'serverInfo', 'name')}"
    puts "   Version: #{init_response.dig('result', 'serverInfo', 'version')}"

    # 2. List available tools
    puts "\n🔧 Listing available tools..."
    tools_response = client.send_request({
                                           jsonrpc: '2.0',
                                           id: 2,
                                           method: 'tools/list'
                                         })

    tools = tools_response.dig('result', 'tools')
    puts "✅ Found #{tools.length} tool(s):"
    tools.each do |tool|
      puts "   - #{tool['name']}: #{tool['description']}"
    end

    # 3. Example tool call - Weaviate query
    puts "\n🔍 Example: Querying Weaviate database..."
    query_response = client.send_request({
                                           jsonrpc: '2.0',
                                           id: 3,
                                           method: 'tools/call',
                                           params: {
                                             name: 'weaviate_query',
                                             arguments: {
                                               class_name: 'Document',
                                               query: 'artificial intelligence and machine learning',
                                               limit: 5,
                                               properties: %w[title content author]
                                             }
                                           }
                                         })

    if query_response['error']
      puts "❌ Query failed: #{query_response['error']['message']}"
      puts '   This is expected if Weaviate is not running or has no data'
    else
      puts '✅ Query executed successfully!'
      result = JSON.parse(query_response.dig('result', 'content', 0, 'text'))
      if result['success']
        puts "   Found data: #{result['data']}"
      else
        puts "   Query error (expected if no Weaviate or data): #{result['error']}"
      end
    end

    # 4. Example with filtering
    puts "\n🎯 Example: Query with filtering..."
    filtered_query_response = client.send_request({
                                                    jsonrpc: '2.0',
                                                    id: 4,
                                                    method: 'tools/call',
                                                    params: {
                                                      name: 'weaviate_query',
                                                      arguments: {
                                                        class_name: 'Article',
                                                        query: 'climate change sustainability',
                                                        limit: 3,
                                                        where_filter: {
                                                          path: 'category',
                                                          operator: 'Equal',
                                                          valueText: 'environment'
                                                        },
                                                        properties: %w[title summary]
                                                      }
                                                    }
                                                  })

    if filtered_query_response['error']
      puts "❌ Filtered query failed: #{filtered_query_response['error']['message']}"
    else
      puts '✅ Filtered query executed successfully!'
      JSON.parse(filtered_query_response.dig('result', 'content', 0, 'text'))
      puts "   Query included where filter for category='environment'"
    end
  rescue StandardError => e
    puts "❌ Error: #{e.message}"
  ensure
    client.close
  end

  puts "\n#{'=' * 50}"
  puts '🎉 Example completed!'
  puts "\nNext steps:"
  puts '1. Start Weaviate: docker compose up -d'
  puts '2. Add some data to your Weaviate instance'
  puts '3. Configure this server in your MCP client (like Cursor)'
  puts '4. Start using semantic search in your AI workflow!'
end

main if __FILE__ == $PROGRAM_NAME
