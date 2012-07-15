class MyShip < ActiveRecord::Base

  self.primary_key = 'id'
  has_many :planets_in_range, :foreign_key => "ship"
  has_many :ships_in_range, :foreign_key => "ship_in_range_of"

  attr_accessor :type
  attr_accessor :objective
  attr_accessor :distance_from_objective
  attr_accessor :queue

  def self.mine_all_planets
    # TODO: This doesn't work
    sql = "UPDATE my_ships SET
		  action='MINE',
		  action_target_id=planets_in_range.planet
	   FROM planets_in_range
	   WHERE my_ships.id=planets_in_range.ship;"
    ActiveRecord::Base.connection.update_sql(sql)
  end

  def upgrade(attribute, amount)
    val = self.class.select("UPGRADE(#{self.id}, '#{attribute}', #{amount})").where(:id => self.id).first.attributes
    if val["upgrade"] == 't'
      self.send("#{attribute.downcase}=", self.send("#{attribute.downcase}") + amount)
      return true
    end
    return false
  end

  def refuel_ship
    self.class.select("REFUEL_SHIP(#{self.id})").where(:id => self.id).first
  end

  def commence_attack(ship_id)
    self.class.select("ATTACK(#{self.id}, #{ship_id})").where(:id => self.id).first
  end

  def repair(ship_id)
    self.class.select("REPAIR(#{self.id}, #{ship_id})").where(:id => self.id).first
  end

  def mine(planet_id)
    self.class.select("MINE(#{self.id}, #{planet_id})").where(:id => self.id).first
  end

  def total_skill
    self.attack + self.defense + self.prospecting + self.engineering
  end

  def course_control(speed, direction = nil, destination = nil)
    dest = destination.nil? ? "NULL" : "POINT('#{destination}')"
    dir = direction.nil? ? "NULL" : direction
    val = self.class.select("SHIP_COURSE_CONTROL(#{self.id}, #{speed}, #{dir}, #{dest})").where(:id => self.id).first.attributes
    if val["ship_course_control"] == 't'
      self.destination = destination
      self.max_speed = speed
      return true
    end
    return false
  end

  def modify_speed
    max_speed_allowed = Functions.get_numeric_variable('MAX_SHIP_SPEED')
    if self.distance_from_objective > self.max_speed && self.max_speed < max_speed_allowed
      upgrade_amount_available = max_speed_allowed - self.max_speed

      # TODO: Find the price of refueling
      price_to_refuel = 1
      available_funds = Schemaverse.estimated_income - (Schemaverse.fuel_needed_for_next_tic * price_to_refuel)
      upgrade_amount = available_funds <= upgrade_amount_available * PriceList.max_speed ? upgrade_amount_available : available_funds / PriceList.max_speed
      self.upgrade('MAX_SHIP_SPEED', upgrade_amount.to_i) if upgrade_amount.to_i > 0
    end
  end

  def process_next_queue_item
    next_objective = queue.first
    if explorer_ship.course_control(Functions.distance_between(self, next_objective) / 2, nil, next_objective)
      self.objective = next_objective
      queue.shift
    end
  end

end