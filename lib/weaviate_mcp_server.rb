#!/usr/bin/env ruby

require 'json'
require 'net/http'
require 'uri'
require 'logger'

class WeaviateMCPServer
  VERSION = '1.0.0'.freeze

  def initialize(weaviate_url: 'http://localhost:8080', logger: nil)
    @weaviate_url = weaviate_url
    @logger = logger || Logger.new($stderr)
    @tools = [
      {
        name: 'weaviate_query',
        description: 'Query data from Weaviate vector database using GraphQL. ' \
                     'Supports semantic search, hybrid search, and filtering.',
        inputSchema: {
          type: 'object',
          properties: {
            class_name: {
              type: 'string',
              description: 'The name of the Weaviate class to query'
            },
            query: {
              type: 'string',
              description: 'The search query text for semantic search'
            },
            limit: {
              type: 'integer',
              description: 'Maximum number of results to return (default: 10)',
              default: 10
            },
            where_filter: {
              type: 'object',
              description: 'Optional where filter for precise filtering'
            },
            properties: {
              type: 'array',
              items: { type: 'string' },
              description: 'Array of properties to return (default: all)'
            }
          },
          required: %w[class_name query]
        }
      }
    ]
  end

  def run
    @logger.info "Starting Weaviate MCP Server v#{VERSION}"

    loop do

      input = $stdin.gets
      break if input.nil?

      request = JSON.parse(input.strip)
      response = handle_request(request)

      $stdout.puts JSON.generate(response)
      $stdout.flush
    rescue JSON::ParserError => e
      @logger.error "JSON parsing error: #{e.message}"
      error_response = {
        jsonrpc: '2.0',
        id: nil,
        error: {
          code: -32_700,
          message: 'Parse error'
        }
      }
      $stdout.puts JSON.generate(error_response)
      $stdout.flush
    rescue StandardError => e
      @logger.error "Unexpected error: #{e.message}"
      @logger.error e.backtrace.join("\n")

    end
  end

  private

  def handle_request(request)
    case request['method']
    when 'initialize'
      handle_initialize(request)
    when 'tools/list'
      handle_tools_list(request)
    when 'tools/call'
      handle_tools_call(request)
    else
      {
        jsonrpc: '2.0',
        id: request['id'],
        error: {
          code: -32_601,
          message: 'Method not found'
        }
      }
    end
  end

  def handle_initialize(request)
    {
      jsonrpc: '2.0',
      id: request['id'],
      result: {
        protocolVersion: '2024-11-05',
        capabilities: {
          tools: {}
        },
        serverInfo: {
          name: 'weaviate-mcp-server',
          version: VERSION
        }
      }
    }
  end

  def handle_tools_list(request)
    {
      jsonrpc: '2.0',
      id: request['id'],
      result: {
        tools: @tools
      }
    }
  end

  def handle_tools_call(request)
    tool_name = request.dig('params', 'name')
    arguments = request.dig('params', 'arguments') || {}

    case tool_name
    when 'weaviate_query'
      result = query_weaviate(arguments)
      {
        jsonrpc: '2.0',
        id: request['id'],
        result: {
          content: [
            {
              type: 'text',
              text: JSON.pretty_generate(result)
            }
          ]
        }
      }
    else
      {
        jsonrpc: '2.0',
        id: request['id'],
        error: {
          code: -32_602,
          message: "Unknown tool: #{tool_name}"
        }
      }
    end
  end

  def query_weaviate(arguments)
    class_name = arguments['class_name']
    query = arguments['query']
    limit = arguments['limit'] || 10
    where_filter = arguments['where_filter']
    properties = arguments['properties'] || ['*']

    graphql_query = build_graphql_query(class_name, query, limit, where_filter, properties)

    uri = URI("#{@weaviate_url}/v1/graphql")
    http = Net::HTTP.new(uri.host, uri.port)

    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = JSON.generate({ query: graphql_query })

    @logger.info "Executing GraphQL query: #{graphql_query}"

    response = http.request(request)

    if response.code == '200'
      result = JSON.parse(response.body)
      if result['errors']
        {
          success: false,
          error: result['errors'],
          query: graphql_query
        }
      else
        {
          success: true,
          data: result['data'],
          query: graphql_query
        }
      end
    else
      {
        success: false,
        error: "HTTP #{response.code}: #{response.message}",
        query: graphql_query
      }
    end
  rescue StandardError => e
    @logger.error "Weaviate query error: #{e.message}"
    {
      success: false,
      error: e.message,
      query: graphql_query
    }
  end

  def build_graphql_query(class_name, query, limit, where_filter, properties)
    properties_str = properties.join(' ')

    query_parts = []
    query_parts << "nearText: { concepts: [\"#{escape_graphql_string(query)}\"] }"
    query_parts << "limit: #{limit}"

    if where_filter
      where_str = build_where_filter(where_filter)
      query_parts << "where: #{where_str}" if where_str
    end

    <<~GRAPHQL
      {
        Get {
          #{class_name}(#{query_parts.join(', ')}) {
            #{properties_str}
            _additional {
              id
              distance
              certainty
            }
          }
        }
      }
    GRAPHQL
  end

  def build_where_filter(filter)
    return nil unless filter.is_a?(Hash)

    # Simple where filter builder - can be extended for more complex cases
    return unless filter['path'] && filter['operator'] && filter['valueText']

    <<~WHERE
      {
        path: ["#{filter['path']}"],
        operator: #{filter['operator']},
        valueText: "#{escape_graphql_string(filter['valueText'])}"
      }
    WHERE
  end

  def escape_graphql_string(str)
    str.to_s.gsub('"', '\\"').gsub("\n", '\\n').gsub("\r", '\\r')
  end
end

# Run the server if this file is executed directly
if __FILE__ == $PROGRAM_NAME
  server = WeaviateMCPServer.new
  server.run
end
