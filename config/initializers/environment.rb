require 'rubygems'
require 'active_record'
require 'yaml'
require 'geo_ruby'
require 'pry'
require 'resque'

if ENV['DATABASE_URL'].nil?
	db_config = YAML::load(File.open('config/database.yml'))

  if ARGV[0].nil? && ARGV[1].nil? && !ENV['ENV'] == 'test'
    USERNAME, PASSWORD = ARGV[0], ARGV[1]
  else
    test_config = YAML::load(File.open('config/test.yml'))
    USERNAME = test_config['username']
    PASSWORD = test_config['password']
  end

  db_config.merge!(:username => USERNAME, :password => PASSWORD)

	ActiveRecord::Base.establish_connection(db_config)
else
	USERNAME = ENV['SCHEMAVERSE_USERNAME']
	ActiveRecord::Base.establish_connection(ENV["DATABASE_URL"])
end

load('config/initializers/db.rb')
load('lib/functions.rb')

#r = Redis.new(:host => "ec2-50-112-202-82.us-west-2.compute.amazonaws.com", :port => 6379)
r = Redis.new(:host => "localhost", :port => 6379)
REDIS = Redis::Namespace.new(USERNAME.to_sym, :redis => r)
