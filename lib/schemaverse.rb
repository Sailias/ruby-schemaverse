class Schemaverse

  include Variables

  def initialize
    #set_up_variables
  end

  def determine_home
    if Planet.where(:name => Planet.my_home_name).empty?
      if @home
        new_home = @home.closest_planets(1).my_planets.first
      else
        new_home = Planet.my_planets.first
      end
      new_home.update_attribute('name', Planet.my_home_name) if new_home
    end
    @home = Planet.home
  end

  def play
    last_tic = 0
    last_round = nil
    set_up_variables

    while true
      # Adding cool names to my planets
      @tic = TicSeq.first.last_value
      @round = RoundSeq.first.last_value
      last_round ||= @round

      #unless last_round.eql?(@round)
      #  puts "A NEW ROUND HAS BEGUN!!"
      #  # RESET EVERYTHING
      #
      #  # Destroy all but 30 ships if there are some already made
      #  puts "A new round has begun"
      #  (MyShip.all - MyShip.first(30)).each do |ship|
      #    ship.destroy
      #  end
      #
      #  determine_home
      #
      #  # Make all existing ships mine home
      #  MyShip.all.update_attribute("action_target_id", @home.id)
      #  set_up_variables
      #end

      if last_tic != @tic
        #sleep(45) # Wait 45 seconds into each round for the data to propagate
        determine_home
        puts "Starting new Tic"
        last_tic = @tic

        puts "loading tic data"
        populate_tic_data

        #handle_interior_ships

        puts "handling planet ships"
        handle_planets_ships

        puts "refueling ships"
        refuel_ships

        #deploy_travelling_ships

        puts "deploying armada groups"
        deploy_armada_groups

        #manage_travelling_ships_actions

        puts "managing armada groups"
        manage_armada_ships_actions

        puts "manage ships in range"
        manage_ships_in_range

        puts "attacking ships"
        attack_ships

        puts "repairing ships"
        repair_ships

      end
    end
  end

  def next_expand_planet(i, start = nil)
    obs = @objective_planets.group_by(&:conqueror_id).to_a.select { |grp| grp.last.size < 2 }.collect { |g| g.last }.flatten
    unless start.nil?
      obs.sort! { |p| Functions.distance_between(p, start) }
      obs = obs.select { |p| Functions.distance_between(p, start) < 1000000 }
    end
    p = obs[i]

    if p.nil?
      p = @objective_planets[i]
    end

    p
  end


  # @param [Object] planet
  def conquer_planet(planet)
    if planet.ships.size < planet.mine_limit # && MyShip.count < 2001
      create_ships_for_planet(planet)
    else
      upgrade_ships_at_planet(planet)
      expand_to_new_planet(planet)
    end
  end

  def create_ships_for_planet(planet)
    total_ships_to_create = (planet.mine_limit + 20 - planet.ships.size) - @trade_ships.select { |ts| ts.location.eql?(planet.location) }.size
    puts "#{planet.name} => SHIPS TO CREATE: #{total_ships_to_create}"
    if total_ships_to_create > 0
      if @ships.size + total_ships_to_create >= @number_of_total_ships_allowed
        # Stash ships at a planet for now
        puts "   Need to free up: #{(@ships.size + total_ships_to_create) - @number_of_total_ships_allowed} ships!"
        free_up_ships((@ships.size + total_ships_to_create) - @number_of_total_ships_allowed)
      end

      @ships + MyShip.create_ships_at(planet.mine_limit - planet.ships.size - @trade_ships.select { |ts| ts.location.eql?(planet.location) && ts.name.include?('miner') }.size, planet, 'miner', 480, 0, 0, 0, 'MINE', planet.id)
      MyShip.create_ships_at(20 - planet.ships.defenders.size - @trade_ships.select { |ts| ts.location.eql?(planet.location) && ts.name.include?('defender') }.size, planet, 'defender', 0, 200, 200, 80, nil, nil)
    end
  end


  ######## TRADE METHODS

  def free_up_ships(n = 0)
    stash_ships(@ships.select { |s| !@ships_in_range.collect(&:ship_in_range_of).include?(s.id) && !s.name.include?('armada') }.first(n))
  end

  def stash_ships_at(planet)
    stash_ships(planet.ships.where("name NOT LIKE ? AND name NOT LIKE ?", "traveller", "armada").offset(1).all)
  end

  def stash_ships(ships)
    TradeItem.trade_ships(ships)
    @trade_ships += ships
    @ships = @ships - ships
  end

  ###########

  def upgrade_ships_at_planet(planet)
    # If I have the same amount of miners on my home planet as the limit allows for, it makes more sense to upgrade the ships instead
    unless planet.ships.average("prospecting+engineering+defense+attack") == @max_ship_skill
      planet.ships.where("(prospecting+engineering+defense+attack) < ?", @max_ship_skill).each do |ship|
        begin
          skill_remaining = @max_ship_skill - ship.total_skill
          num_upgrades = @my_player.total_resources / PriceList.prospecting
          upgrade_amount = num_upgrades > skill_remaining ? skill_remaining.to_i : num_upgrades.to_i
          if upgrade_amount > 0
            puts "upgrading ship skill by #{upgrade_amount}"
            if (@planets.size > 25 || @tic > 80) && upgrade_amount / 2 > 1
              half_upgrade = (upgrade_amount / 2).to_i
              @my_player.convert_fuel_to_money((half_upgrade * PriceList.prospecting).to_i) if @my_player.balance < (half_upgrade * PriceList.prospecting)
              ship.upgrade('PROSPECTING', half_upgrade)
              ship.update_attribute("name", "#{planet.name}-miner") unless ship.name.include?("armada") || ship.name.include?("traveller")
              @my_player.balance -= half_upgrade * PriceList.prospecting

              @my_player.convert_fuel_to_money((half_upgrade * PriceList.attack).to_i) if @my_player.balance < (half_upgrade * PriceList.attack)
              ship.upgrade('ATTACK', half_upgrade)
              ship.update_attribute("name", "#{planet.name}-miner") unless ship.name.include?("armada") || ship.name.include?("traveller")
              @my_player.balance -= half_upgrade * PriceList.attack
            else
              @my_player.convert_fuel_to_money((upgrade_amount * PriceList.prospecting).to_i) if @my_player.balance < (upgrade_amount * PriceList.prospecting)
              ship.upgrade('PROSPECTING', upgrade_amount)
              ship.update_attribute("name", "#{planet.name}-miner") unless ship.name.include?("armada") || ship.name.include?("traveller")
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

  def expand_to_new_planet(expand_planet)
    # Our miners are getting maxed, lets build a ship and send him to the next closest planet
    #planet.closest_planets(10).where("conqueror_id <> ?", @my_player.id).select { |p| !@ships.collect(&:objective).include?(p) }.each do |expand_planet|
    #unless @planets.include?(expand_planet)
    # This is still a planet we need to capture
    explorer_object = calculate_efficient_travel(expand_planet)
    if explorer_object.is_a?(Planet)
      if ship = MyShip.create_ships_at(1, explorer_object, 'traveller', 80, 150, 150, 100, 'MINE', expand_planet.id).first
        if ship.course_control((Functions.distance_between(explorer_object, expand_planet) / 2).to_i, nil, expand_planet.location)
          ship.objective = expand_planet
          @travelling_ships << ship
          @objective_planets.delete(expand_planet)
          @ships << ship
        end
      end
    elsif explorer_object.is_a?(MyShip) #&& explorer_object.type == "Travelling"
                                        #puts "Travelling ship #{explorer_object.name} is queued to travel to #{expand_planet.name}"
                                        #explorer_object.queue += expand_planet
                                        # Do nothing because this ship is still travelling
                                        #puts "The closest object to #{expand_planet.name} is the ship #{explorer_object.id}:#{explorer_object.name}"
      if explorer_object.at_destination? && (@planets.include?(explorer_object.objective) || explorer_object.ships_in_range.size > 0)
        puts "The ship #{explorer_object.name} is now travelling to #{expand_planet.name}"
        if explorer_object.course_control((Functions.distance_between(explorer_object, expand_planet) / 2).to_i, nil, expand_planet.location)
          explorer_object.objective = expand_planet
          explorer_object.update_attributes(:action => "ATTACK", :action_target_id => nil)
          @objective_planets.delete(expand_planet)
        end
      end
    end
    #end
    #end
  end

  def calculate_efficient_travel(to)
    # first calculate if a new ship were to go there
    closest_planet = @planets.sort { |p| Functions.distance_between(p, to) }.first

    # calculate the closest travelling ship and it's distance to it's target and the distance
    # from the target to our target destination

    if @travelling_ships.size > 0
      closest_travelling_ship = @travelling_ships.sort { |ts|
        (ts.distance_from_objective + Functions.distance_between(ts.objective, to)) / ts.max_speed
      }.first
    end

    vals = {}
    vals.merge!(closest_planet => Functions.distance_between(closest_planet, to) / (PriceList.ship + Schemaverse.available_income(@ships))) if @travelling_ships.size < @number_of_travelling_ships
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


  def handle_interior_ships
    # Start killing of ships at planets that in my interior
    @planets.sort_by { |p| Functions.distance_between(p, @home) }.each do |planet|
      begin

        #  conquer_planet(planet)
        #
        if planet.closest_planets(3).select { |p| p.conqueror_id != @my_player.id }.empty? && @mining_ships.size >= @number_of_miners_allowed
          stash_ships_at(planet)
          #else
          #  planet.closest_planets(3).select { |p| p.conqueror_id != @my_player.id }.each do |p|
          #    @armada_planets.unshift(p) unless @armada_planets.include?(p) || @armada_targets.include?(p)
          #  end
        end
      rescue
      end
    end
  end

  def handle_planets_ships
    @planets.sort_by { |p| Functions.distance_between(p, @home) }.reverse.each do |planet|
      create_ships_for_planet(planet)
    end
  end

  def refuel_ships
    puts "Checking for armada travelling that are out of fuel"
    @armada_ships.select { |s| !s.at_destination? && s.current_fuel < s.speed }.group_by(&:destination).to_a.each do |grp|
      total_fuel_for_group = grp.last.sum(&:max_fuel)
      if @my_player.fuel_reserve >= total_fuel_for_group
        grp.last.each do |ship|
          puts "Refueling #{ship.name}"
          ship.refuel_ship rescue nil
          @my_player.fuel_reserve -= ship.max_fuel - ship.current_fuel
        end
      end
    end

    ## Ships that are out of fuel that haven't reached their destination
    #puts "Checking for ships travelling that are out of fuel"
    #@travelling_ships.select { |s| !s.at_destination? && s.current_fuel < (s.max_fuel / 2) }.each do |ship|
    #  if @my_player.fuel_reserve > ship.max_fuel
    #    puts "Refueling #{ship.name}"
    #    ship.refuel_ship rescue nil
    #    @my_player.fuel_reserve -= ship.max_fuel - ship.current_fuel
    #  end
    #end
  end

  def deploy_travelling_ships
    # Expand to new planets based on tic
    if @travelling_ships.size <= @tic / 3 && @travelling_ships.size < @number_of_travelling_ships
      ((@tic / 3) - @travelling_ships.size).to_i.times do |i|
        expand_to_new_planet(next_expand_planet(i, @home))
      end
    end
  end

  def deploy_armada_groups
    puts "Number of armada groups: #{@armada_ships.group_by(&:objective).size}"
    if @armada_ships.each_slice(@number_of_ships_in_armada).to_a.size < @number_of_armada_groups

      (@number_of_armada_groups - @armada_ships.each_slice(@number_of_ships_in_armada).to_a.size).times do
        begin

          # Create another group of amada ships if you can
          cost_of_attack_fleet = ((PriceList.ship) +
            (PriceList.defense * 200) +
            (PriceList.attack * 200) +
            (Functions.get_numeric_variable('MAX_SHIP_FUEL') / 3) +
            (Functions.get_numeric_variable('MAX_SHIP_SPEED') / 3)
          ) * @number_of_ships_in_armada

          puts "Attack fleet cost: #{cost_of_attack_fleet}"

          if @my_player.total_resources >= cost_of_attack_fleet

            if @ships.size >= @number_of_total_ships_allowed
              #@mining_ships.first(@number_of_ships_in_armada).each do |miner_ship|
              #  miner_ship.destroy
              #end
              free_up_ships(@number_of_ships_in_armada)
            end

            @my_player.convert_fuel_to_money(cost_of_attack_fleet.to_i) if @my_player.balance < cost_of_attack_fleet
            planet_to_conquer = @objective_planets.first
            if planet_to_conquer
              closest_planet_to_objective = planet_to_conquer.closest_planets(1).my_planets.first
              @number_of_ships_in_armada.times do
                begin
                  armada_ship = MyShip.create(
                    :name => "#{USERNAME}-armada",
                    :prospecting => 5,
                    :attack => 5,
                    :defense => 5,
                    :engineering => 5,
                    :location => closest_planet_to_objective.location
                  )

                  if armada_ship.id?
                    puts "New ARMADA SHIP"
                    armada_ship = armada_ship.reload
                    armada_ship.update_attributes(:action => "ATTACK")
                    armada_ship.upgrade("ATTACK", 200)
                    armada_ship.upgrade("DEFENSE", 200)
                    armada_ship.upgrade("MAX_FUEL", (Functions.get_numeric_variable('MAX_SHIP_FUEL') / 3).to_i)
                    armada_ship.upgrade("MAX_SPEED", (Functions.get_numeric_variable('MAX_SHIP_SPEED') / 3).to_i)
                    @my_player.balance -= cost_of_attack_fleet

                    if armada_ship.course_control((Functions.distance_between(armada_ship, planet_to_conquer) / 2).to_i, nil, planet_to_conquer.location)

                      armada_ship.objective = planet_to_conquer
                      @armada_ships << armada_ship
                      @armada_planets.delete(planet_to_conquer)
                      @armada_targets << planet_to_conquer
                    end

                    # Load the ship into our array
                    @ships << armada_ship
                  end
                rescue Exception => e
                  puts e.message
                end
              end
            end
          end
        rescue
        end
      end
    end
  end

  def manage_travelling_ships_actions
    # handle all travelling ships
    @travelling_ships.sort_by(&:distance_from_objective).each do |travelling_ship|
      begin
        if travelling_ship.at_destination?
          if travelling_ship.objective.is_a?(Planet)
            if @planets.include?(travelling_ship.objective) || travelling_ship.ships_in_range.size > 0
              # Lets move this ship to another planet!
              new_planet = next_expand_planet(0, travelling_ship)
              if travelling_ship.course_control(travelling_ship.max_speed, nil, new_planet.location)
                travelling_ship.objective = new_planet
                @objective_planets.delete(new_planet)
              end

              if travelling_ship.ships_in_range.size > 0
                # lets do something here to capture this planet
                # @armada_planets << travelling_ship.objective
              end

            else
              puts "#{travelling_ship.name} is at the location. Mining#{travelling_ship.objective.name}"
              travelling_ship.update_attributes(:action => "MINE", :action_target_id => travelling_ship.objective.id)
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
      rescue Exception => e
        puts e.message
      end
    end

  end

  def manage_armada_ships_actions
    @armada_ships.group_by(&:objective).each do |armada_ship_grp|
      begin
        if armada_ship_grp.last[0].at_destination?

          armada_ship_grp.last.each do |armada_ship|
            armada_ship.update_attributes(:action => "MINE", :action_target_id => armada_ship.objective.id)
          end

          if @planets.include?(armada_ship_grp.first)
            #new_armada_planet = @armada_planets.sort_by { |p| Functions.distance_between(p, armada_ship_grp.last[0]) }.first
            new_armada_planet = armada_ship_grp.first.closest_planets(1).not_my_planets.first
            if new_armada_planet
              puts "MISSION COMPLETE!! MOVE ON"
              puts "moving ships to #{new_armada_planet.name}"
              armada_ship_grp.last.each do |armada_ship|
                if armada_ship.course_control(armada_ship.max_speed, nil, new_armada_planet.location)
                  armada_ship.objective = new_armada_planet
                  armada_ship.update_attributes(:action => "ATTACK", :action_target_id => nil)
                end
              end
              @armada_planets.delete(new_armada_planet)
              @armada_targets << new_armada_planet
            end
          end
        end
      rescue
      end
    end
  end

  def manage_ships_in_range
    @ships_in_range.each do |sir|
      s = @ships.select { |s| s.id.eql?(sir.ship_in_range_of) }.first
      if s
        ships_to_pop = @trade_ships.select { |ts| Functions.distance_between(ts, s) < 300 }
        free_up_ships(ships_to_pop.size)
        TradeItem.delete_trades(ships_to_pop.collect(&:id))
        @trade_ships = @trade_ships - ships_to_pop
      end
    end
  end

  def attack_ships
    puts "Checking for ships to attack"
    attacking_ships = []
    MyShip.joins(:ships_in_range).all.uniq.each do |s|
      begin
        attack_ship = s.ships_in_range.all.select { |s| !attacking_ships.include?(s) }.first
        unless attack_ship.nil?
          attacking_ships << attack_ship
          begin
            s.commence_attack(attack_ship.id)
          rescue Exception => e
            # Row locking was occurring on mass upgrading
            puts e.message
          end
        end
      rescue
      end
    end
  end

  def repair_ships
    # Repair ships
    puts "Checking for ships to repair"
    @ships.select { |s| s.current_health < 100 }.each do |hurt_ship|
      begin
        @ships.select { |s| Functions.distance_between(s, hurt_ship) <= s.range && !s.eql?(hurt_ship) }.each do |repair_ship|
          repair_ship.repair(hurt_ship.id)
        end
      rescue
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
