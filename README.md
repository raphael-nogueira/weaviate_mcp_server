# Weaviate MCP Server

[![Ruby](https://img.shields.io/badge/Ruby-3.1.0-red.svg)](https://www.ruby-lang.org/)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/Tests-RSpec-green.svg)](https://rspec.info/)
[![Linter](https://img.shields.io/badge/Linter-RuboCop-brightgreen.svg)](https://rubocop.org/)
[![MCP](https://img.shields.io/badge/Protocol-MCP-orange.svg)](https://modelcontextprotocol.io/)
[![Docker](https://img.shields.io/badge/Docker-Compose-blue.svg)](https://docs.docker.com/compose/)

A Model Context Protocol (MCP) server implementation for Weaviate vector database, enabling seamless Retrieval-Augmented Generation (RAG) capabilities and eliminating file quantity limitations in AI assistants like Cursor.

## 🚀 Features

- **Single Tool Interface**: Simple `weaviate_query` tool for semantic search operations
- **Semantic Search**: Leverages Weaviate's vector search capabilities for context-aware queries
- **Flexible Filtering**: Support for GraphQL-based filtering and property selection
- **Docker Integration**: Simple single-node Weaviate setup via Docker Compose
- **Comprehensive Testing**: Full test suite with mocks, stubs, and VCR for external resources
- **Production Ready**: Error handling, logging, and robust MCP protocol implementation

## 📋 Prerequisites

- Ruby 3.4.3 or higher
- Docker and Docker Compose
- Bundler gem

## 🛠️ Installation

1. **Clone the repository:**
   ```bash
   git clone https://github.com/your-username/weaviate_mcp_server.git
   cd weaviate_mcp_server
   ```

2. **Install dependencies:**
   ```bash
   bundle install
   ```

3. **Setup development environment:**
   ```bash
   rake setup
   ```

4. **Start Weaviate:**
   ```bash
   docker compose up -d
   ```

## 🚀 Quick Start

### 1. Start Weaviate Database

```bash
# Start Weaviate in the background
docker compose up -d

# Check if Weaviate is running
curl http://localhost:8080/v1/.well-known/ready
```

### 2. Run the MCP Server

```bash
# Using the executable script
./bin/weaviate-mcp-server

# Or using rake task
rake server

# With custom Weaviate URL
WEAVIATE_URL=http://custom-host:8080 ./bin/weaviate-mcp-server
```

### 3. Configure in Cursor

Add the following to your Cursor MCP configuration:

```json
{
  "mcpServers": {
    "weaviate": {
      "command": "/path/to/weaviate_mcp_server/bin/weaviate-mcp-server",
      "args": []
    }
  }
}
```

## 🔧 Usage

The server provides a single tool called `weaviate_query` that allows you to perform semantic searches on your Weaviate database.

### Tool Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `class_name` | string | Yes | The name of the Weaviate class to query |
| `query` | string | Yes | The search query text for semantic search |
| `limit` | integer | No | Maximum number of results (default: 10) |
| `where_filter` | object | No | Optional where filter for precise filtering |
| `properties` | array | No | Array of properties to return (default: all) |

### Example Queries

**Basic semantic search:**
```json
{
  "class_name": "Document",
  "query": "artificial intelligence machine learning",
  "limit": 5
}
```

**Search with filtering:**
```json
{
  "class_name": "Article",
  "query": "climate change",
  "limit": 10,
  "where_filter": {
    "path": "category",
    "operator": "Equal",
    "valueText": "science"
  },
  "properties": ["title", "content", "author"]
}
```

## 🐳 Docker Configuration

The included `compose.yml` provides a simple single-node Weaviate setup suitable for local development:

- **Port 8080**: Weaviate REST API
- **Port 50051**: Weaviate gRPC API  
- **Anonymous access**: Enabled for simplicity
- **Persistent storage**: Data stored in named volume
- **Health checks**: Automatic container health monitoring

### Customizing Weaviate

To modify the Weaviate configuration, edit the `compose.yml` file. Common customizations:

```yaml
environment:
  # Add OpenAI API key for text vectorization
  OPENAI_APIKEY: "your-api-key"
  
  # Enable different modules
  ENABLE_MODULES: 'text2vec-openai,generative-openai'
  
  # Adjust default limits
  QUERY_DEFAULTS_LIMIT: 50
```

## 🧪 Testing

The project includes comprehensive tests using RSpec with mocking for external dependencies.

```bash
# Run all tests
bundle exec rspec

# Run tests with coverage
bundle exec rspec --format documentation

# Run specific test file
bundle exec rspec spec/weaviate_mcp_server_spec.rb

# Run linting
bundle exec rubocop

# Run both tests and linting
rake ci
```

### Test Structure

- **Unit Tests**: Complete coverage of server functionality
- **Mocking**: All external HTTP requests are mocked using WebMock
- **VCR Integration**: Ready for recording real API interactions
- **Error Scenarios**: Comprehensive error handling validation

## 📁 Project Structure

```
weaviate_mcp_server/
├── bin/
│   └── weaviate-mcp-server          # Executable script
├── lib/
│   └── weaviate_mcp_server.rb       # Main server implementation
├── spec/
│   ├── spec_helper.rb               # Test configuration
│   ├── weaviate_mcp_server_spec.rb  # Main test suite
│   └── vcr_cassettes/               # VCR recordings (if used)
├── compose.yml                      # Weaviate Docker setup
├── Gemfile                          # Ruby dependencies
├── Rakefile                         # Build tasks
├── .rspec                           # RSpec configuration
├── .gitignore                       # Git ignore rules
├── LICENSE                          # MIT license
└── README.md                        # This file
```

## 🔧 Development

### Available Rake Tasks

```bash
rake setup           # Setup development environment
rake spec            # Run tests
rake rubocop         # Run linting
rake ci              # Run tests and linting
rake server          # Start MCP server
rake weaviate        # Start Weaviate with Docker Compose
rake weaviate_stop   # Stop Weaviate
```

### Adding New Features

1. **Extend the tool schema** in `lib/weaviate_mcp_server.rb`
2. **Add query building logic** in the `build_graphql_query` method
3. **Write comprehensive tests** in `spec/weaviate_mcp_server_spec.rb`
4. **Update documentation** in this README

### Code Quality

The project maintains high code quality through:

- **RuboCop**: Enforces Ruby style guidelines
- **RSpec**: Comprehensive test coverage
- **Mocking**: No external dependencies in tests
- **Error Handling**: Robust error handling and logging

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass (`rake ci`)
6. Commit your changes (`git commit -am 'Add amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

## 📊 Performance Considerations

- **Connection Pooling**: Consider implementing connection pooling for high-volume usage
- **Caching**: Add result caching for frequently accessed data
- **Async Operations**: Implement async queries for better performance
- **Resource Limits**: Configure appropriate memory and CPU limits in Docker

## 🔒 Security Notes

- The default configuration uses anonymous access for simplicity
- For production use, implement proper authentication
- Consider network security when exposing Weaviate ports
- Validate and sanitize all user inputs

## 📝 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙋‍♂️ Support

- **Issues**: Report bugs and request features via [GitHub Issues](https://github.com/your-username/weaviate_mcp_server/issues)
- **Discussions**: Join the conversation in [GitHub Discussions](https://github.com/your-username/weaviate_mcp_server/discussions)
- **Documentation**: Additional docs at [Model Context Protocol](https://modelcontextprotocol.io/)
- **Weaviate Docs**: [Weaviate Documentation](https://weaviate.io/developers/weaviate)

## 🌟 Acknowledgments

- [Model Context Protocol](https://modelcontextprotocol.io/) for the MCP specification
- [Weaviate](https://weaviate.io/) for the excellent vector database
- [Ruby Community](https://www.ruby-lang.org/) for the amazing ecosystem
- [Cursor](https://cursor.sh/) for inspiring this integration

---

**Made with ❤️ for the AI and Ruby communities** 