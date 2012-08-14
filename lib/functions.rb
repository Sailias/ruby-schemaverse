class Functions
  class << self

    # Returns the id for the given player name   
    def get_player_id(player_name)      
      ActiveRecord::Base.connection.execute("SELECT GET_PLAYER_ID(#{player_name}) as player_id").first["player_id"]
    end

    # Returns the username for the given player id
    def get_player_username(player_id)
      ActiveRecord::Base.connection.execute("SELECT GET_PLAYER_USERNAME(#{player_id}) as player_username").first["player_username"]
    end

    def get_numeric_variable(var)
      ActiveRecord::Base.connection.execute("SELECT GET_NUMERIC_VARIABLE('#{var}') as numeric_variable").first["numeric_variable"].to_f
    end

    def db_distance_between(point_a, point_b)
      ActiveRecord::Base.connection.execute("SELECT POINT('#{point_a}') <-> POINT('#{point_b}') as distance").first["distance"].to_f
    end

    def distance_between(obj_a, obj_b)
      p1 = GeoRuby::SimpleFeatures::Point.from_x_y(get_x(obj_a), get_y(obj_a))
      p2 = GeoRuby::SimpleFeatures::Point.from_x_y(get_x(obj_b), get_y(obj_b))
      p1.euclidian_distance(p2)
    end

    def get_x(obj)
      obj.location.split(",").first[1..-1].to_f
    end

    def get_y(obj)
      obj.location.split(',').last.chop.to_f
    end

    def distance_between_strs(str_a, str_b)
      p1 = GeoRuby::SimpleFeatures::Point.from_x_y(get_x_for_str(str_a), get_y_for_str(str_a))
      p2 = GeoRuby::SimpleFeatures::Point.from_x_y(get_x_for_str(str_b), get_y_for_str(str_b))
      p1.euclidian_distance(p2)
    end

    def get_x_for_str(str)
      str.split(",").first[1..-1].to_f
    end

    def get_y_for_str(str)
      str.split(',').last.chop.to_f
    end
    
  end

end