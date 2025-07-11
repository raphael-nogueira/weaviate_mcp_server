require 'rspec/core/rake_task'
require 'rubocop/rake_task'

# Default task
task default: %i[spec rubocop]

# RSpec task
RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = 'spec/**/*_spec.rb'
  t.rspec_opts = '--color --format documentation'
end

# RuboCop task
RuboCop::RakeTask.new(:rubocop) do |t|
  t.options = ['--display-cop-names']
end

# Task to run the MCP server
task :server do
  exec 'ruby bin/weaviate-mcp-server'
end

# Task to start Weaviate with Docker Compose
task :weaviate do
  exec 'docker compose up'
end

# Task to stop Weaviate
task :weaviate_stop do
  exec 'docker compose down'
end

desc 'Run all tests and linting'
task ci: %i[spec rubocop]

desc 'Setup development environment'
task :setup do
  puts 'Installing gems...'
  system 'bundle install'

  puts 'Creating directories...'
  FileUtils.mkdir_p('spec/vcr_cassettes')

  puts 'Setup complete!'
end
