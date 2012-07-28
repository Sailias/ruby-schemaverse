class Schemaverse
  def initialize
    if Planet.where(:name => Planet.my_home_name).empty?
      new_home = Planet.my_planets.first
      new_home.update_attribute('name', Planet.my_home_name) if new_home
    end

    set_up_variables
  end

  def set_up_variables
    @my_player = MyPlayer.first
    @home = Planet.home
    @max_ship_skill = Functions.get_numeric_variable('MAX_SHIP_SKILL')
    @max_ship_fuel = Functions.get_numeric_variable('MAX_SHIP_FUEL')
    @ships = MyShip.all
    @travelling_ships = []

    @ships.each do |ship|
      unless ship.destination.blank?
        ship.objective = Planet.where("location ~= POINT(?)", ship.destination).first
        if ship.objective
          ship.distance_from_objective = Functions.distance_between(ship, ship.objective)
          if !ship.at_destination? || (ship.at_destination? && ship.objective.conqueror_id != @my_player.id)
            # STORE travelling ships here!
            REDIS.rpush "travelling_ships", ship.attributes.to_json
            @travelling_ships << ship
          end
        end
      end
    end

    @armada_ships = []
    @lost_ships = []
    @my_planets = Planet.my_planets.all
    @objective_planets = []
    @lost_planets = []
    @tic = 0

    Planet.not_my_planets.select("id, name, location, conqueror_id, planets.location<->POINT('#{@home.location}') as distance").order("distance ASC").each do |planet|
      REDIS.rpush 'objective_planets', planet.attributes.to_json
      @objective_planets << planet
    end
  end

  def play
    last_tic = 0
    set_up_variables

    while true
      # Adding cool names to my planets
      @tic = TicSeq.first.last_value
      if @tic == 1
        set_up_variables
      end

      sleep(1)
      if last_tic != @tic
        puts "Starting new Tic"
        last_tic = @tic
        Planet.my_planets.not_home.where("name NOT LIKE ?", "%#{USERNAME}%").each_with_index do |planet, i|
          planet.update_attribute('name', Planet.get_new_planet_name(i.to_s))
        end

        @my_player = MyPlayer.first

        my_planets = []
        my_planets = Planet.my_planets.order("planets.location<->POINT('#{@home.location}') DESC").all if @home
        new_planets = my_planets - @planets
        @lost_planets += @planets - my_planets
        @planets = my_planets

        my_ships = MyShip.all
        new_ships = my_ships - @ships
        @lost_ships += @ships - my_ships
        @ships = @ships - @lost_ships

        @travelling_ships = []

        # Update all my travelling ships
        my_ships.each do |ship|
          REDIS.lrange('travelling_ships', 0, REDIS.llen('travelling_ships')).each_with_index do |redis_ship, i|
            attrs = JSON.parse redis_ship
            if ship.id == redis_ship['id']
              # We found our ship in redis
              REDIS.lset "travelling_ships", i, ship.attributes.to_json
              @travelling_ships << ship
            end
          end
        end

        # Remove all destroyed ships from our travelling ships
        @lost_ships.each do |ship|
          REDIS.lrange('travelling_ships', 0, REDIS.llen('travelling_ships')).each_with_index do |redis_ship, i|
            attrs = JSON.parse redis_ship
            if ship.id == redis_ship['id']
              # We found our ship in redis AND IT HAS BEEN DESTROYED!!
              REDIS.lrem "travelling_ships", 0, redis_ship
              if ship.objective
                planet = ship.objective
                if @travelling_ships.select{|s| s.objective}
              end
            end
          end
        end

        #@travelling_ships = @ships.select { |s| s.type == "Travelling" }
        #@armada_ships = @ships.select { |s| s.type == "Armada" }

        # Ships that are out of fuel that haven't reached their destination
        puts "Checking for ships travelling that are out of fuel"
        @travelling_ships.select { |s| !s.at_destination? && s.current_fuel < (s.max_fuel / 2) }.each do |ship|
          if @my_player.fuel_reserve > ship.max_fuel
            puts "Refueling #{ship.name}"
            ship.refuel_ship
            @my_player.fuel_reserve -= ship.max_fuel - ship.current_fuel
          end
        end

        # Start killing of ships at planets that in my interior
        @planets.each do |planet|
          conquer_planet(planet)

          if planet.closest_planets(5).select{ |p| p.conqueror_id != @my_player.id }.empty?
            planet.ships.each do |ship|
              # Have all the ships at the planet destroy themselves.
              # TODO, just put these ships into trade!
              ship.commence_attack(ship.id)
            end
          end
        end

        # handle all travelling ships
        @travelling_ships.each do |travelling_ship|
          if travelling_ship.at_destination?
            if travelling_ship.objective.is_a?(Planet)
              if travelling_ship.ships_in_range.blank?
                puts "#{travelling_ship.name} is at the location. Mining#{travelling_ship.objective.name}"
                travelling_ship.update_attributes(:action => "MINE", :action_target_id => travelling_ship.objective.id)
              else
                begin
                  #call_for_reinforcements(travelling_ship) if !travelling_ship.objective.conqueror_id.eql?(@my_player.id) && (@ships - [travelling_ship]).select { |s| s.destination == travelling_ship.destination }.empty?
                  travelling_ship.update_attributes(:action => "ATTACK", :action_target_id => nil)
                rescue Exception => e
                  puts e.message
                end
              end
            else
              # Something else needs to happen here
            end
          else
            begin
              travelling_ship.modify_speed(@ships)
              travelling_ship.modify_fuel(@ships)
            rescue Exception => e
              puts e.message
            end
          end

          #if @planets.include?(travelling_ship.objective)
          #  puts "Processing queue"
          #  travelling_ship.process_next_queue_item
          #end
        end

        #@armada_ships.each do |armada_ship|
        #  unless armada_ship.at_destination?
        #    begin
        #      armada_ship.modify_speed(@ships)
        #      armada_ship.modify_fuel(@ships)
        #    rescue Exception => e
        #      puts e.message
        #    end
        #  else
        #    if armada_ship.ships_in_range.empty?
        #      travelling_ship.update_attributes(:action => "MINE", :action_target_id => armada_ship.objective.id)
        #    end
        #  end
        #end

        puts "Checking for ships to attack"
        MyShip.joins(:ships_in_range).each do |attack_ship|
          begin
            attack_ship.commence_attack(attack_ship.ships_in_range.first.id) unless attack_ship.ships_in_range.empty?
          rescue Exception => e
            # Row locking was occurring on mass upgrading
            puts e.message
          end
        end
      end
    end
  end

  # @param [Object] planet
  def conquer_planet(planet)
    if planet.ships.size < planet.mine_limit && MyShip.count < 2001
      create_ships_for_planet(planet)
    else
      puts "#{planet.name} has maxed out on miners"
      upgrade_ships_at_planet(planet)
      expand_to_new_planet(planet)
    end
  end

  def create_ships_for_planet(planet)
    puts "This planet needs ships"
    (planet.mine_limit - planet.ships.size).times do
      if @my_player.balance < PriceList.ship
        @my_player.convert_fuel_to_money(PriceList.ship)
      end

      # If you can build another miner at this planet, do so
      ship = planet.ships.create(
        :name => "#{planet.name}-miner",
        :prospecting => 5,
        :attack => 5,
        :defense => 5,
        :engineering => 5,
        :location => planet.location
      )

      if ship.id
        @my_player.balance -= PriceList.ship
        ship = ship.reload
        ship.update_attributes(:action => "MINE", :action_target_id => planet.id)
        # Load the ship into our array
        @ships << ship
        puts "Created a ship for #{planet.name}"
      else
        # Break out of this loop if the ship could not be created
        puts "ERROR CREATING SHIP"
        break
      end
      break if planet.ships.size >= planet.mine_limit
    end
  end

  def upgrade_ships_at_planet(planet)
    # If I have the same amount of miners on my home planet as the limit allows for, it makes more sense to upgrade the ships instead
    unless planet.ships.average("prospecting+engineering+defense+attack") == @max_ship_skill
      planet.ships.where("(prospecting+engineering+defense+attack) < ?", @max_ship_skill).each do |ship|
        begin
          skill_remaining = @max_ship_skill - ship.total_skill
          num_upgrades = @my_player.total_resources / PriceList.prospecting
          upgrade_amount = num_upgrades > skill_remaining ? skill_remaining.to_i : num_upgrades.to_i
          puts "upgrading ship skill by #{upgrade_amount}"
          if upgrade_amount > 0
            if (@planets.size > 25 || @tic > 80) && upgrade_amount / 2 > 1
              half_upgrade = (upgrade_amount / 2).to_i
              @my_player.convert_fuel_to_money((half_upgrade * PriceList.prospecting).to_i) if @my_player.balance < (half_upgrade * PriceList.prospecting)
              ship.upgrade('PROSPECTING', half_upgrade)
              ship.update_attribute("name", "#{planet.name}-miner")
              @my_player.balance -= half_upgrade * PriceList.prospecting

              @my_player.convert_fuel_to_money((half_upgrade * PriceList.attack).to_i) if @my_player.balance < (half_upgrade * PriceList.attack)
              ship.upgrade('ATTACK', half_upgrade)
              ship.update_attribute("name", "#{planet.name}-miner")
              @my_player.balance -= half_upgrade * PriceList.attack
            else
              @my_player.convert_fuel_to_money((upgrade_amount * PriceList.prospecting).to_i) if @my_player.balance < (upgrade_amount * PriceList.prospecting)
              ship.upgrade('PROSPECTING', upgrade_amount)
              ship.update_attribute("name", "#{planet.name}-miner")
              @my_player.balance -= upgrade_amount * PriceList.prospecting
            end
          end

        rescue Exception => e
          # Row locking was occurring on mass upgrading
          puts e.message
        end
      end
    end
  end

  def expand_to_new_planet(planet)
    # Our miners are getting maxed, lets build a ship and send him to the next closest planet
    planet.closest_planets(10).where("conqueror_id <> ?", @my_player.id).select{|p| !@ships.collect(&:objective).include?(p) }.each do |expand_planet|
      unless @planets.include?(expand_planet)
        # This is still a planet we need to capture
        explorer_object = calculate_efficient_travel(planet)
        if explorer_object.is_a?(Planet)
          @my_player.convert_fuel_to_money(PriceList.ship) if @my_player.balance < PriceList.ship
          explorer_ship = explorer_object.ships.create(
            :name => "#{USERNAME}-traveller",
            :prospecting => 5,
            :attack => 5,
            :defense => 5,
            :engineering => 5,
            :location => explorer_object.location
          )

          if explorer_ship.id?
            @my_player.balance -= PriceList.ship
            puts "New Ship created sending to #{expand_planet.name}"
            explorer_ship = explorer_ship.reload
            explorer_ship.update_attributes(:action => "ATTACK")
            if explorer_ship.course_control((Functions.distance_between(explorer_object, expand_planet) / 2).to_i, nil, expand_planet.location)
              explorer_ship.type = "Travelling"
              explorer_ship.objective = expand_planet
              #@travelling_ships << explorer_ship
            end

            # Load the ship into our array
            @ships << explorer_ship

          end
        elsif explorer_object.is_a?(Ship) && explorer_object.type == "Travelling"
          puts "Travelling ship #{explorer_object.name} is queued to travel to #{expand_planet.name}"
          explorer_object.queue += expand_planet
        end
      end
    end
  end

  def calculate_efficient_travel(to)
    # first calculate if a new ship were to go there
    closest_planet = @planets.sort { |p| Functions.distance_between(p, to) }.first

    # calculate the closest travelling ship and it's distance to it's target and the distance
    # from the target to our target destination
    if @ships.select { |s| s.type.eql?("Travelling" && !s.objective.nil?) }.size < 25
      closest_travelling_ship = @ships.select { |s| s.type.eql?("Travelling" && !s.objective.nil?) }.sort { |ts|
        (ts.distance_from_objective + Functions.distance_between(ts.objective, to)) / ts.max_speed
      }.first
    end

    vals = {closest_planet => Functions.distance_between(closest_planet, to) / (PriceList.ship + Schemaverse.available_income(@ships))} if @ships.size < 2000
    vals.merge!(closest_travelling_ship => Functions.distance_between(closest_travelling_ship.objective, to) / (PriceList.ship + Schemaverse.available_income(@ships))) if closest_travelling_ship

    unless vals.empty?
      # Return the object to send
      vals.sort_by { |name, tics| tics }.to_a.first[0]
    else
      return nil
    end

  end

  def call_for_reinforcements(ship)
    planet = ship.objective.closest_planets.where("conqueror_id = ?", @my_player.id).first
    if planet && @my_player.total_resources >= (PriceList.ship + (PriceList.attack * 200) + (PriceList.defense * 200)) * 20
      20.times do
        cost = PriceList.ship + (PriceList.attack * 200) + (PriceList.defense * 200)
        @my_player.convert_fuel_to_money(cost) if @my_player.balance < cost
        armada_ship = MyShip.create(
          :name => "#{USERNAME}-armada",
          :prospecting => 5,
          :attack => 5,
          :defense => 5,
          :engineering => 5,
          :location => planet.location
        )

        if armada_ship.id?
          @my_player.balance -= PriceList.ship
          puts "New Ship created sending to #{planet.name}"
          armada_ship = armada_ship.reload
          armada_ship.update_attributes(:action => "ATTACK")

          @my_player.convert_fuel_to_money((200 * PriceList.attack).to_i) if @my_player.balance < (200 * PriceList.attack)
          armada_ship.upgrade('ATTACK', 200)
          armada_ship.update_attribute("name", "#{USERNAME}-armada")
          @my_player.balance -= 200 * PriceList.attack

          @my_player.convert_fuel_to_money((200 * PriceList.attack).to_i) if @my_player.balance < (200 * PriceList.attack)
          armada_ship.upgrade('DEFENSE', 200)
          armada_ship.update_attribute("name", "#{USERNAME}-armada")
          @my_player.balance -= 200 * PriceList.defense

          if armada_ship.course_control((Functions.distance_between(armada_ship, planet) / 2).to_i, nil, ship.location)
            armada_ship.type = "Armada"
            armada_ship.objective = ship.objective
          end

          # Load the ship into our array
          puts "Sending aramda ship to #{ship.objective.name}"
          @ships << armada_ship
        end
      end
    end

  end

  class << self

    def fuel_needed_for_next_tic(ships)
      ships.select { |s| s.type.eql?("Travelling") }.inject(0) do |result, ship|
        # Keep the fuel above 50% at all times
        if ship.current_fuel < (ship.max_fuel / 2)
          result += ship.max_fuel - ship.current_fuel
        else
          result += 0
        end
      end
    end

    def estimated_income(ships)
      mining_gain_per_prospecting = 16.5
      ships.select { |s| s.action && s.action.strip == 'MINE' }.sum(&:prospecting) * mining_gain_per_prospecting
    end

    def total_expenses(ships)
      price_for_fuel = 1
      Schemaverse.fuel_needed_for_next_tic(ships) * price_for_fuel
    end

    def available_income(ships)
      Schemaverse.estimated_income(ships) - Schemaverse.total_expenses(ships)
    end
  end

end