require_relative File.join("..", "", "my_player.rb")

Dir.glob(File.join('lib', 'models', '*.rb')).each do |file|
  require_relative File.join("..", "..", file)
end

require 'redis'
require 'redis-namespace'