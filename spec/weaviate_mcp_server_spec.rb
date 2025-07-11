require 'spec_helper'
require 'json'
require 'logger'

RSpec.describe WeaviateMCPServer do
  let(:logger) { instance_double(Logger) }
  let(:server) { described_class.new(weaviate_url: 'http://test-weaviate:8080', logger: logger) }

  before do
    allow(logger).to receive(:info)
    allow(logger).to receive(:error)
  end

  describe '#initialize' do
    it 'sets the weaviate URL and logger' do
      expect(server.instance_variable_get(:@weaviate_url)).to eq('http://test-weaviate:8080')
      expect(server.instance_variable_get(:@logger)).to eq(logger)
    end

    it 'defines weaviate_query tool' do
      tools = server.instance_variable_get(:@tools)
      expect(tools).to have_attributes(size: 1)

      tool = tools.first
      expect(tool[:name]).to eq('weaviate_query')
      expect(tool[:description]).to include('Query data from Weaviate vector database')
      expect(tool[:inputSchema][:required]).to eq(%w[class_name query])
    end
  end

  describe '#handle_request' do
    let(:request) { { 'method' => method_name, 'id' => 123 } }

    context 'when method is initialize' do
      let(:method_name) { 'initialize' }

      it 'returns initialization response' do
        response = server.send(:handle_request, request)

        expect(response[:jsonrpc]).to eq('2.0')
        expect(response[:id]).to eq(123)
        expect(response[:result][:protocolVersion]).to eq('2024-11-05')
        expect(response[:result][:serverInfo][:name]).to eq('weaviate-mcp-server')
        expect(response[:result][:serverInfo][:version]).to eq('1.0.0')
      end
    end

    context 'when method is tools/list' do
      let(:method_name) { 'tools/list' }

      it 'returns tools list' do
        response = server.send(:handle_request, request)

        expect(response[:jsonrpc]).to eq('2.0')
        expect(response[:id]).to eq(123)
        expect(response[:result][:tools]).to have_attributes(size: 1)
        expect(response[:result][:tools].first[:name]).to eq('weaviate_query')
      end
    end

    context 'when method is tools/call' do
      let(:method_name) { 'tools/call' }
      let(:request) do
        {
          'method' => 'tools/call',
          'id' => 123,
          'params' => {
            'name' => 'weaviate_query',
            'arguments' => {
              'class_name' => 'Document',
              'query' => 'test query'
            }
          }
        }
      end

      before do
        allow(server).to receive(:query_weaviate).and_return({
                                                               success: true,
                                                               data: { 'Get' => { 'Document' => [] } }
                                                             })
      end

      it 'calls the weaviate_query tool and returns result' do
        response = server.send(:handle_request, request)

        expect(response[:jsonrpc]).to eq('2.0')
        expect(response[:id]).to eq(123)
        expect(response[:result][:content]).to have_attributes(size: 1)
        expect(response[:result][:content].first[:type]).to eq('text')
      end
    end

    context 'when method is unknown' do
      let(:method_name) { 'unknown_method' }

      it 'returns method not found error' do
        response = server.send(:handle_request, request)

        expect(response[:jsonrpc]).to eq('2.0')
        expect(response[:id]).to eq(123)
        expect(response[:error][:code]).to eq(-32_601)
        expect(response[:error][:message]).to eq('Method not found')
      end
    end
  end

  describe '#query_weaviate' do
    let(:arguments) do
      {
        'class_name' => 'Document',
        'query' => 'test query',
        'limit' => 5,
        'properties' => %w[title content]
      }
    end

    let(:mock_response) { instance_double(Net::HTTPResponse) }
    let(:mock_http) { instance_double(Net::HTTP) }

    before do
      allow(Net::HTTP).to receive(:new).and_return(mock_http)
      allow(mock_http).to receive(:request).and_return(mock_response)
    end

    context 'when request is successful' do
      let(:weaviate_response) do
        {
          'data' => {
            'Get' => {
              'Document' => [
                {
                  'title' => 'Test Document',
                  'content' => 'Test content',
                  '_additional' => {
                    'id' => '123',
                    'distance' => 0.1,
                    'certainty' => 0.9
                  }
                }
              ]
            }
          }
        }
      end

      before do
        allow(mock_response).to receive(:code).and_return('200')
        allow(mock_response).to receive(:body).and_return(JSON.generate(weaviate_response))
      end

      it 'returns successful response with data' do
        result = server.send(:query_weaviate, arguments)

        expect(result[:success]).to be true
        expect(result[:data]).to eq(weaviate_response['data'])
        expect(result[:query]).to include('Document')
        expect(result[:query]).to include('test query')
      end
    end

    context 'when Weaviate returns errors' do
      let(:weaviate_response) do
        {
          'errors' => [
            { 'message' => 'Class not found' }
          ]
        }
      end

      before do
        allow(mock_response).to receive(:code).and_return('200')
        allow(mock_response).to receive(:body).and_return(JSON.generate(weaviate_response))
      end

      it 'returns error response' do
        result = server.send(:query_weaviate, arguments)

        expect(result[:success]).to be false
        expect(result[:error]).to eq(weaviate_response['errors'])
      end
    end

    context 'when HTTP request fails' do
      before do
        allow(mock_response).to receive(:code).and_return('500')
        allow(mock_response).to receive(:message).and_return('Internal Server Error')
      end

      it 'returns HTTP error response' do
        result = server.send(:query_weaviate, arguments)

        expect(result[:success]).to be false
        expect(result[:error]).to include('HTTP 500')
      end
    end

    context 'when network error occurs' do
      before do
        allow(mock_http).to receive(:request).and_raise(StandardError.new('Connection failed'))
      end

      it 'returns network error response' do
        result = server.send(:query_weaviate, arguments)

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Connection failed')
      end
    end
  end

  describe '#build_graphql_query' do
    it 'builds basic GraphQL query' do
      query = server.send(:build_graphql_query, 'Document', 'test', 10, nil, %w[title content])

      expect(query).to include('Get')
      expect(query).to include('Document')
      expect(query).to include('nearText: { concepts: ["test"] }')
      expect(query).to include('limit: 10')
      expect(query).to include('title content')
      expect(query).to include('_additional')
    end

    it 'includes where filter when provided' do
      where_filter = {
        'path' => 'category',
        'operator' => 'Equal',
        'valueText' => 'news'
      }

      query = server.send(:build_graphql_query, 'Document', 'test', 10, where_filter, ['title'])

      expect(query).to include('where:')
      expect(query).to include('category')
      expect(query).to include('Equal')
      expect(query).to include('news')
    end
  end

  describe '#build_where_filter' do
    it 'builds where filter for text values' do
      filter = {
        'path' => 'category',
        'operator' => 'Equal',
        'valueText' => 'news'
      }

      result = server.send(:build_where_filter, filter)

      expect(result).to include('path: ["category"]')
      expect(result).to include('operator: Equal')
      expect(result).to include('valueText: "news"')
    end

    it 'returns nil for invalid filter' do
      result = server.send(:build_where_filter, {})
      expect(result).to be_nil
    end

    it 'returns nil for non-hash input' do
      result = server.send(:build_where_filter, 'invalid')
      expect(result).to be_nil
    end
  end

  describe '#escape_graphql_string' do
    it 'escapes quotes' do
      result = server.send(:escape_graphql_string, 'text with "quotes"')
      expect(result).to eq('text with \\"quotes\\"')
    end

    it 'escapes newlines' do
      result = server.send(:escape_graphql_string, "line1\nline2")
      expect(result).to eq('line1\\nline2')
    end

    it 'escapes carriage returns' do
      result = server.send(:escape_graphql_string, "line1\rline2")
      expect(result).to eq('line1\\rline2')
    end

    it 'converts non-strings to strings' do
      result = server.send(:escape_graphql_string, 123)
      expect(result).to eq('123')
    end
  end
end
