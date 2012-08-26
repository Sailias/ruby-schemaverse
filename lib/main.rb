raise "Username and Password Required" unless (ENV['ENV'] = 'test' || ARGV[0] && ARGV[1]) || (ENV['DATABASE_URL'] && ENV['SCHEMAVERSE_USERNAME'])
load('config/initializers/environment.rb')
require_relative 'variables'
require_relative 'schemaverse'

Schemaverse.new.play




