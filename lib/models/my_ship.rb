class MyShip < ActiveRecord::Base

  self.primary_key = 'id'
  belongs_to :my_player, :foreign_key => "player_id"
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

  def modify_speed(ships)
    max_speed_allowed = Functions.get_numeric_variable('MAX_SHIP_SPEED')
    if self.distance_from_objective > self.max_speed && self.max_speed < max_speed_allowed
      upgrade_amount_available = max_speed_allowed - self.max_speed
      #available_funds = Schemaverse.estimated_income(ships) - (Schemaverse.fuel_needed_for_next_tic(ships))
      #upgrade_amount = available_funds <= upgrade_amount_available * PriceList.max_speed ? available_funds / PriceList.max_speed : upgrade_amount_available
      upgrade_amount = upgrade_amount_available / 3

      player = self.my_player

      if upgrade_amount.to_i > 0 && upgrade_amount * PriceList.max_speed <= player.total_resources
        MyPlayer.first.convert_fuel_to_money(upgrade_amount.to_i * PriceList.max_speed) if player.balance < upgrade_amount.to_i * PriceList.max_speed
        if self.upgrade('MAX_SPEED', upgrade_amount.to_i)
          puts "upgrading #{self.name} speed #{upgrade_amount}"
          self.update_attribute("target_speed", self.max_speed)
        end
      end
    end
  end

  def modify_fuel(ships)
    max_fuel_allowed = Functions.get_numeric_variable('MAX_SHIP_FUEL')
    # Don't upgrade if we can reach our destination in 3 tics or less
    if (self.distance_from_objective / self.speed) > 3 && self.max_fuel < max_fuel_allowed
      upgrade_amount_available = max_fuel_allowed - self.max_fuel
      upgrade_amount_available = self.max_speed if self.max_speed < upgrade_amount_available
      #available_funds = Schemaverse.estimated_income(ships) - Schemaverse.fuel_needed_for_next_tic(ships)
      #upgrade_amount = available_funds <= upgrade_amount_available * PriceList.max_fuel ? available_funds / PriceList.max_fuel : upgrade_amount_available
      upgrade_amount = upgrade_amount_available / 3

      if upgrade_amount.to_i > 0 && upgrade_amount * PriceList.max_fuel < my_player.total_resources
        MyPlayer.first.convert_fuel_to_money(upgrade_amount.to_i * PriceList.max_fuel) if MyPlayer.first.balance < upgrade_amount.to_i * PriceList.max_fuel
        if self.upgrade('MAX_FUEL', upgrade_amount.to_i)
          puts "upgrading #{self.name} fuel #{upgrade_amount}"
        end
      end

    end
  end

  def process_next_queue_item
    unless self.queue.nil?
      next_objective = self.queue.first
      if next_objective
        if explorer_ship.course_control(Functions.distance_between(self, next_objective) / 2, nil, next_objective)
          self.objective = next_objective
          queue.shift
        end
      end
    end
  end

  def at_destination?
    distance_from_objective <= self.range
  end

end