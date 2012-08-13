class MyShip < ActiveRecord::Base

  self.primary_key = 'id'
  belongs_to :my_player, :foreign_key => "player_id"
  has_many :planets_in_range, :foreign_key => "ship"
  has_many :ships_in_range, :foreign_key => "ship_in_range_of"

  scope :with_name_like, lambda{|n|
    where("name LIKE ?", "%#{n}%")
  }

  scope :defenders, with_name_like("defender")

  attr_accessor :type
  attr_accessor :objective
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

  def self.create_ships_at(number, planet, name_type, prospecting, attack, defense, engineering, action, action_target_id)
    ships = []
    return ships if number < 1

    player = MyPlayer.first
    total_resources = player.total_resources
    balance = player.balance

    cost_of_ship = PriceList.ship + (PriceList.prospecting * prospecting) + (PriceList.attack * attack) + (PriceList.defense * defense) + (PriceList.engineering * engineering)
    loop_num = (total_resources / cost_of_ship).to_i >= number ? number : (total_resources / cost_of_ship).to_i
    total_cost = cost_of_ship * loop_num

    loop_num.times do
      begin
        if balance < total_cost
          player.convert_fuel_to_money(total_cost - balance)
        end

        # If you can build another miner at this planet, do so
        ship = planet.ships.create(
          :name => "#{planet.name}-#{name_type}",
          :prospecting => 5,
          :attack => 5,
          :defense => 5,
          :engineering => 5,
          :location => planet.location
        )

        if ship.id
          ship = ship.reload
          ship.update_attributes(:action => action, :action_target_id => action_target_id)
          ship.upgrade("PROSPECTING", prospecting) if prospecting > 0
          ship.upgrade("ATTACK", attack) if attack > 0
          ship.upgrade("DEFENSE", defense) if defense > 0
          ship.upgrade("ENGINEERING", engineering) if engineering > 0
          ships << ship
          puts "Created a ship for #{planet.name}"
        else
          # Break out of this loop if the ship could not be created
          puts "ERROR CREATING SHIP"
          break
        end
      rescue Exception => e
        puts e.message
      end
    end unless total_resources < total_cost
    return ships
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
    begin
      dest = destination.nil? ? "NULL" : "POINT('#{destination}')"
      dir = direction.nil? ? "NULL" : direction
      val = self.class.select("SHIP_COURSE_CONTROL(#{self.id}, #{speed}, #{dir}, #{dest})").where(:id => self.id).first.attributes
      if val["ship_course_control"] == 't'
        self.destination = destination
        self.max_speed = speed
        return true
      end
      return false
    rescue
    end
  end

  def modify_speed(ships)
    max_speed_allowed = Functions.get_numeric_variable('MAX_SHIP_SPEED')
    if self.distance_from_objective > self.max_speed && self.max_speed < max_speed_allowed
      upgrade_amount_available = max_speed_allowed - self.max_speed
      #available_funds = Schemaverse.estimated_income(ships) - (Schemaverse.fuel_needed_for_next_tic(ships))
      #upgrade_amount = available_funds <= upgrade_amount_available * PriceList.max_speed ? available_funds / PriceList.max_speed : upgrade_amount_available

      player = MyPlayer.first

      upgrade_amount = upgrade_amount_available / 3
      upgrade_amount = player.total_resources / 2 / PriceList.max_speed if upgrade_amount * PriceList.max_speed > player.total_resources

      if upgrade_amount.to_i > 0
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
    if (self.max_speed / self.max_fuel) > 3 && self.max_fuel < max_fuel_allowed
      upgrade_amount_available = max_fuel_allowed - self.max_fuel
      upgrade_amount_available = self.max_speed if self.max_speed < upgrade_amount_available
      #available_funds = Schemaverse.estimated_income(ships) - Schemaverse.fuel_needed_for_next_tic(ships)
      #upgrade_amount = available_funds <= upgrade_amount_available * PriceList.max_fuel ? available_funds / PriceList.max_fuel : upgrade_amount_available

      player = MyPlayer.first

      upgrade_amount = upgrade_amount_available / 3
      upgrade_amount = player.total_resources / 2 / PriceList.max_speed if upgrade_amount * PriceList.max_speed > player.total_resources

      if upgrade_amount.to_i > 0
        MyPlayer.first.convert_fuel_to_money(upgrade_amount.to_i * PriceList.max_fuel) if player.balance < upgrade_amount.to_i * PriceList.max_fuel
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

  def distance_from_objective
    Functions.distance_between(self, self.objective)
  end

  def at_destination?
    distance_from_objective <= self.range
  end


end
