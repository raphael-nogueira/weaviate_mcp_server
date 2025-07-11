#!/usr/bin/env ruby

require 'json'
require 'net/http'
require 'uri'
require 'csv'
require 'optparse'
require 'logger'
require 'fileutils'

class WeaviateKnowledgeBasePopulator
  attr_reader :weaviate_url, :logger

  def initialize(weaviate_url: 'http://localhost:8080', logger: nil)
    @weaviate_url = weaviate_url
    @logger = logger || Logger.new($stdout)
    @logger.level = Logger::INFO
  end

  def populate_from_file(file_path, options = {})
    unless File.exist?(file_path)
      @logger.error "File not found: #{file_path}"
      return false
    end

    case File.extname(file_path).downcase
    when '.json'
      populate_from_json(file_path, options)
    when '.csv'
      populate_from_csv(file_path, options)
    when '.txt', '.md'
      populate_from_text(file_path, options)
    else
      @logger.error "Unsupported file format: #{File.extname(file_path)}"
      false
    end
  end

  def populate_from_json(file_path, options = {})
    @logger.info "Loading documents from JSON file: #{file_path}"
    
    begin
      data = JSON.parse(File.read(file_path))
      class_name = options[:class_name] || 'Document'
      
      # Ensure class exists
      ensure_class_exists(class_name, options[:schema])
      
      # Handle both array and single object
      documents = data.is_a?(Array) ? data : [data]
      
      success_count = 0
      documents.each_with_index do |doc, index|
        if create_document(class_name, doc)
          success_count += 1
          @logger.info "Document #{index + 1}/#{documents.length} added successfully"
        else
          @logger.error "Failed to add document #{index + 1}/#{documents.length}"
        end
      end
      
      @logger.info "Successfully added #{success_count}/#{documents.length} documents"
      true
    rescue JSON::ParserError => e
      @logger.error "JSON parsing error: #{e.message}"
      false
    rescue StandardError => e
      @logger.error "Error processing JSON file: #{e.message}"
      false
    end
  end

  def populate_from_csv(file_path, options = {})
    @logger.info "Loading documents from CSV file: #{file_path}"
    
    begin
      class_name = options[:class_name] || 'Document'
      text_column = options[:text_column] || 'content'
      title_column = options[:title_column] || 'title'
      
      # Ensure class exists
      ensure_class_exists(class_name, options[:schema])
      
      success_count = 0
      CSV.foreach(file_path, headers: true).with_index do |row, index|
        doc = {}
        row.headers.each do |header|
          doc[header] = row[header]
        end
        
        # Ensure required fields
        doc['content'] = doc[text_column] if doc[text_column]
        doc['title'] = doc[title_column] if doc[title_column]
        
        if create_document(class_name, doc)
          success_count += 1
          @logger.info "Document #{index + 1} added successfully"
        else
          @logger.error "Failed to add document #{index + 1}"
        end
      end
      
      @logger.info "Successfully added #{success_count} documents from CSV"
      true
    rescue StandardError => e
      @logger.error "Error processing CSV file: #{e.message}"
      false
    end
  end

  def populate_from_text(file_path, options = {})
    @logger.info "Loading document from text file: #{file_path}"
    
    begin
      content = File.read(file_path)
      class_name = options[:class_name] || 'Document'
      
      # Ensure class exists
      ensure_class_exists(class_name, options[:schema])
      
      # Split content into chunks if requested
      if options[:chunk_size]
        chunks = split_into_chunks(content, options[:chunk_size])
        success_count = 0
        
        chunks.each_with_index do |chunk, index|
          doc = {
            'title' => "#{File.basename(file_path)} - Part #{index + 1}",
            'content' => chunk,
            'source_file' => file_path,
            'chunk_index' => index
          }
          
          if create_document(class_name, doc)
            success_count += 1
            @logger.info "Chunk #{index + 1}/#{chunks.length} added successfully"
          else
            @logger.error "Failed to add chunk #{index + 1}/#{chunks.length}"
          end
        end
        
        @logger.info "Successfully added #{success_count}/#{chunks.length} chunks"
      else
        doc = {
          'title' => File.basename(file_path),
          'content' => content,
          'source_file' => file_path
        }
        
        if create_document(class_name, doc)
          @logger.info "Document added successfully"
          true
        else
          @logger.error "Failed to add document"
          false
        end
      end
    rescue StandardError => e
      @logger.error "Error processing text file: #{e.message}"
      false
    end
  end

  def ensure_class_exists(class_name, custom_schema = nil)
    if class_exists?(class_name)
      @logger.info "Class '#{class_name}' already exists"
      return true
    end

    @logger.info "Creating class '#{class_name}'"
    schema = custom_schema || default_schema(class_name)
    create_class(schema)
  end

  def class_exists?(class_name)
    uri = URI("#{@weaviate_url}/v1/schema/#{class_name}")
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Get.new(uri)
    
    response = http.request(request)
    response.code == '200'
  rescue StandardError => e
    @logger.error "Error checking if class exists: #{e.message}"
    false
  end

  def create_class(schema)
    uri = URI("#{@weaviate_url}/v1/schema")
    http = Net::HTTP.new(uri.host, uri.port)
    
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = JSON.generate(schema)
    
    response = http.request(request)
    
    if response.code == '200'
      @logger.info "Class created successfully"
      true
    else
      @logger.error "Failed to create class: #{response.code} - #{response.body}"
      false
    end
  rescue StandardError => e
    @logger.error "Error creating class: #{e.message}"
    false
  end

  def create_document(class_name, properties)
    uri = URI("#{@weaviate_url}/v1/objects")
    http = Net::HTTP.new(uri.host, uri.port)
    
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    
    object_data = {
      'class' => class_name,
      'properties' => properties
    }
    
    request.body = JSON.generate(object_data)
    
    response = http.request(request)
    
    if ['200', '201'].include?(response.code)
      true
    else
      @logger.error "Failed to create document: #{response.code} - #{response.body}"
      false
    end
  rescue StandardError => e
    @logger.error "Error creating document: #{e.message}"
    false
  end

  def default_schema(class_name)
    {
      'class' => class_name,
      'description' => "Knowledge base documents for class #{class_name}",
      'vectorizer' => 'text2vec-openai',
      'moduleConfig' => {
        'text2vec-openai' => {
          'model' => 'ada',
          'type' => 'text'
        }
      },
      'properties' => [
        {
          'name' => 'title',
          'dataType' => ['text'],
          'description' => 'Title of the document'
        },
        {
          'name' => 'content',
          'dataType' => ['text'],
          'description' => 'Main content of the document'
        },
        {
          'name' => 'source_file',
          'dataType' => ['text'],
          'description' => 'Source file path'
        },
        {
          'name' => 'category',
          'dataType' => ['text'],
          'description' => 'Category or tag for the document'
        },
        {
          'name' => 'author',
          'dataType' => ['text'],
          'description' => 'Author of the document'
        },
        {
          'name' => 'created_at',
          'dataType' => ['date'],
          'description' => 'Creation date'
        },
        {
          'name' => 'chunk_index',
          'dataType' => ['int'],
          'description' => 'Chunk index for split documents'
        }
      ]
    }
  end

  def split_into_chunks(text, chunk_size)
    words = text.split(/\s+/)
    chunks = []
    current_chunk = []
    current_size = 0
    
    words.each do |word|
      if current_size + word.length + 1 > chunk_size && !current_chunk.empty?
        chunks << current_chunk.join(' ')
        current_chunk = [word]
        current_size = word.length
      else
        current_chunk << word
        current_size += word.length + 1
      end
    end
    
    chunks << current_chunk.join(' ') unless current_chunk.empty?
    chunks
  end

  def list_classes
    uri = URI("#{@weaviate_url}/v1/schema")
    http = Net::HTTP.new(uri.host, uri.port)
    request = Net::HTTP::Get.new(uri)
    
    response = http.request(request)
    
    if response.code == '200'
      schema = JSON.parse(response.body)
      classes = schema['classes'] || []
      
      @logger.info "Found #{classes.length} classes:"
      classes.each do |cls|
        @logger.info "  - #{cls['class']}: #{cls['description']}"
      end
      
      classes
    else
      @logger.error "Failed to list classes: #{response.code} - #{response.body}"
      []
    end
  rescue StandardError => e
    @logger.error "Error listing classes: #{e.message}"
    []
  end

  def count_documents(class_name)
    query = <<~GRAPHQL
      {
        Aggregate {
          #{class_name} {
            meta {
              count
            }
          }
        }
      }
    GRAPHQL

    uri = URI("#{@weaviate_url}/v1/graphql")
    http = Net::HTTP.new(uri.host, uri.port)
    
    request = Net::HTTP::Post.new(uri)
    request['Content-Type'] = 'application/json'
    request.body = JSON.generate({ query: query })
    
    response = http.request(request)
    
    if response.code == '200'
      result = JSON.parse(response.body)
      count = result.dig('data', 'Aggregate', class_name, 0, 'meta', 'count') || 0
      @logger.info "Class '#{class_name}' contains #{count} documents"
      count
    else
      @logger.error "Failed to count documents: #{response.code} - #{response.body}"
      0
    end
  rescue StandardError => e
    @logger.error "Error counting documents: #{e.message}"
    0
  end
end

# CLI Interface
def main
  options = {
    weaviate_url: 'http://localhost:8080',
    class_name: 'Document',
    chunk_size: nil,
    text_column: 'content',
    title_column: 'title',
    verbose: false
  }

  OptionParser.new do |opts|
    opts.banner = "Usage: #{$0} [options] <file_path>"
    opts.separator ""
    opts.separator "Options:"

    opts.on('-u', '--url URL', 'Weaviate URL (default: http://localhost:8080)') do |url|
      options[:weaviate_url] = url
    end

    opts.on('-c', '--class CLASS', 'Weaviate class name (default: Document)') do |class_name|
      options[:class_name] = class_name
    end

    opts.on('-s', '--chunk-size SIZE', Integer, 'Split text into chunks of this size') do |size|
      options[:chunk_size] = size
    end

    opts.on('-t', '--text-column COLUMN', 'CSV column for text content (default: content)') do |column|
      options[:text_column] = column
    end

    opts.on('--title-column COLUMN', 'CSV column for title (default: title)') do |column|
      options[:title_column] = column
    end

    opts.on('-v', '--verbose', 'Verbose logging') do
      options[:verbose] = true
    end

    opts.on('-l', '--list-classes', 'List existing classes and exit') do
      options[:list_classes] = true
    end

    opts.on('--count CLASS', 'Count documents in class and exit') do |class_name|
      options[:count_class] = class_name
    end

    opts.on('-h', '--help', 'Show this help message') do
      puts opts
      exit
    end
  end.parse!

  # Initialize populator
  logger = Logger.new($stdout)
  logger.level = options[:verbose] ? Logger::DEBUG : Logger::INFO
  populator = WeaviateKnowledgeBasePopulator.new(
    weaviate_url: options[:weaviate_url],
    logger: logger
  )

  # Handle special commands
  if options[:list_classes]
    populator.list_classes
    exit
  end

  if options[:count_class]
    populator.count_documents(options[:count_class])
    exit
  end

  # Require file path for main operation
  if ARGV.empty?
    puts "Error: Please specify a file path"
    puts "Use #{$0} -h for help"
    exit 1
  end

  file_path = ARGV[0]
  
  puts "🚀 Weaviate Knowledge Base Populator"
  puts "=" * 50
  puts "File: #{file_path}"
  puts "Class: #{options[:class_name]}"
  puts "Weaviate URL: #{options[:weaviate_url]}"
  puts "=" * 50

  success = populator.populate_from_file(file_path, options)
  
  if success
    puts "\n✅ Knowledge base population completed successfully!"
    populator.count_documents(options[:class_name])
  else
    puts "\n❌ Knowledge base population failed!"
    exit 1
  end
end

main if __FILE__ == $PROGRAM_NAME 