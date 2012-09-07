class Schemaverse

  include Variables

  def initialize
    #set_up_variables
  end

  def play
    last_tic = 0
    last_round = nil
    set_up_variables

    while true
      begin
        # Adding cool names to my planets
        @tic = TicSeq.first.last_value
        @round = RoundSeq.first.last_value
        last_round ||= @round

        unless last_round.eql?(@round)
          last_round = @round
          puts "A NEW ROUND HAS BEGUN!!"
          # RESET EVERYTHING

          # Destroy all but 30 ships if there are some already made
          puts "A new round has begun"
          (MyShip.all - MyShip.first(30)).each do |ship|
            ship.destroy
          end

          determine_home

          # Make all existing ships mine home
          MyShip.all.each do |s|
            s.update_attribute("action_target_id", @home.id)
          end
          set_up_variables
        end

        if last_tic != @tic
          #sleep(45) # Wait 45 seconds into each round for the data to propagate
          determine_home
          puts "Starting new Tic"
          last_tic = @tic

          #@trade_ships = []

          populate_tic_data
          upgrade_bad_travellers
          handle_interior_ships if @ships.size > @number_of_total_ships_allowed - 200
          handle_planets_ships if @home
          refuel_ships if @tic % 2 == 0

          manage_armada_ships_actions
          deploy_armada_groups

          attack_ships

          if @home && (@tic < 150 || @my_player.total_resources > 100000000)
            @number_of_travelling_ships = @tic / 2
            deploy_travelling_ships
          end

          @planets_to_create_objects.each do |arr|
            Resque.enqueue(CreateShipsAtPlanet, arr[0], arr[1], arr[2], arr[3])
          end

          @travellers_to_deploy.each do |travs|
            Resque.enqueue(TravellingShips, travs[0], travs[1], travs[2])
          end

          @armadas_to_deploy.each do |armad|
            Resque.enqueue(ArmadaShips, armad[0], armad[1], armad[2])
          end

          manage_travelling_ships_actions
          #handle_lost_planets
          #manage_ships_in_range

          repair_ships
          MyShip.mine_all_planets

          puts "End of tic actions, waiting for a new tic!"

        end
      rescue Exception => e
        puts e.message
        puts e.backtrace
      end
    end
  end

  def next_expand_planet(i, start = nil)
    #obs = @objective_planets.group_by(&:conqueror_id).to_a.select { |grp| grp.last.size < 2 }.collect { |g| g.last }.flatten
    obs = @objective_planets
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

  def get_create_count_for_planet(planet)
    miners_to_create = planet.mine_limit - @ships.select { |ts| ts.location.eql?(planet.location) && ts.name.include?("miner") }.size
    defenders_to_create = 20 - @ships.select { |ts| ts.location.eql?(planet.location) && ts.name.include?("defender") }.size
    return miners_to_create + defenders_to_create
  end

  def create_ships_for_planet(planet)
    miners_to_create = (planet.mine_limit - @ships.select { |ts| ts.location.eql?(planet.location) && ts.name.include?("miner") }.size)

    defenders_to_create = 0
    repairers_to_create = 0
    if @tic > 25
      defenders_to_create = (5 - @ships.select { |ts| ts.location.eql?(planet.location) && ts.name.include?("defender") }.size)
      repairers_to_create = (5 - @ships.select { |ts| ts.location.eql?(planet.location) && ts.name.include?("repairer") }.size)
    end

    puts "#{planet.name} => MINERS TO CREATE: #{miners_to_create}, DEFENDERS TO CREATE: #{defenders_to_create}, REPAIRERS: #{repairers_to_create}"
    @planets_to_create_objects << [planet.id, miners_to_create, defenders_to_create, repairers_to_create] if miners_to_create > 0 || defenders_to_create > 0 || repairers_to_create > 0

  end

  ######## TRADE METHODS

  def free_up_ships(n = 0)
    if n > 0
      #my_ships_with_enemy_ships = @ships_in_range.select { |s| !s.player_id.zero? }.collect(&:ship_in_range_of)
      #ships_to_stash = @ships.select { |s| !my_ships_with_enemy_ships.include?(s.id) && !s.name.include?('armada') }.sort_by { |s| rand(1000) }.first(n)
      ships_to_stash = @ships.select { |s| !s.name.include?('armada') }.first(n)
      return stash_ships(ships_to_stash)
    end
  end

  def stash_ships_at(planet)
    stash_ships(planet.ships.where("name NOT LIKE ? AND name NOT LIKE ?", "%traveller%", "%armada%").offset(1).all)
  end

  def stash_ships(ships)
    TradeItem.trade_ships(ships)
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
    #explorer_object = calculate_efficient_travel(expand_planet)
    #if explorer_object.is_a?(Planet)

    #Resque.enqueue(TravellingShips, expand_planet.id, (@max_ship_fuel / 2).to_i, (@max_ship_speed / 2).to_i)
    @travellers_to_deploy << [expand_planet.id, (@max_ship_fuel / 2).to_i, (@max_ship_speed / 2).to_i]
    #
    #elsif explorer_object.is_a?(MyShip) #&& explorer_object.type == "Travelling"
    #                                    #puts "Travelling ship #{explorer_object.name} is queued to travel to #{expand_planet.name}"
    #                                    #explorer_object.queue += expand_planet
    #                                    # Do nothing because this ship is still travelling
    #                                    #puts "The closest object to #{expand_planet.name} is the ship #{explorer_object.id}:#{explorer_object.name}"
    #  if explorer_object.at_destination? && (@planets.include?(explorer_object.objective) || explorer_object.ships_in_range.size > 0)
    #    puts "The ship #{explorer_object.name} is now travelling to #{expand_planet.name}"
    #    if explorer_object.course_control((Functions.distance_between(explorer_object, expand_planet) / 2).to_i, nil, expand_planet.location)
    #      explorer_object.objective = expand_planet
    #      explorer_object.update_attributes(:action => "ATTACK", :action_target_id => nil)
    #      @objective_planets.delete(expand_planet)
    #    end
    #  end
    #end
    #end
    #end
  end

  def calculate_efficient_travel(to)
    # first calculate if a new ship were to go there
    closest_planet = @planets.sort { |p| Functions.distance_between(p, to) }.first

    # calculate the closest travelling ship and it's distance to it's targetload('config/initializers/environment.rb') and the distance
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
    puts "handling interior planets"
    # Start killing of ships at planets that in my interior
    @planets.sort_by { |p| Functions.distance_between(p, @home) }.each do |planet|
      begin
        if planet.closest_planets(3).select { |p| p.conqueror_id != @my_player.id }.empty? && @mining_ships.size >= @number_of_miners_allowed
          ActiveRecord::Base.connection.execute("DELETE FROM my_ships WHERE id IN(#{planet.ships.collect(&:id)})")
        end
      rescue
      end
    end
  end

  def handle_planets_ships
    puts "handling planet ships"
    #@planets.sort_by { |p| Functions.distance_between(p, @home) }.reverse.select { |p| @ships.select { |s| s.location.eql?(p.location) }.size < p.mine_limit + 20 }.first(10).each do |planet|
    @planets.sort_by { |p| Functions.distance_between(p, @home) }.reverse.select{|planet| !planet.closest_planets(3).select { |p| p.conqueror_id != @my_player.id }.empty? }.each do |planet|
      create_ships_for_planet(planet)
    end
  end

  def refuel_ships
    puts "Checking for armada travelling that are out of fuel"

    ships_to_refuel = []
    @armada_ships.select { |s| !s.at_destination? && s.current_fuel < s.speed }.group_by(&:destination).to_a.each do |grp|
      total_fuel_for_group = grp.last.sum { |s| s.max_fuel - s.current_fuel }
      if @my_player.total_resources >= total_fuel_for_group
        ships_to_refuel += grp.last
        @my_player.fuel_reserve -= total_fuel_for_group
      end
    end

    if @tic < 150 || @my_player.total_resources > 100000000
      puts "Checking for ships travelling that are out of fuel"
      @travelling_ships.select { |s| !s.at_destination? && s.current_fuel < s.speed }.sort_by { |s| s.distance_from_objective }.each do |ship|
        if @my_player.fuel_reserve > ship.max_fuel - ship.current_fuel
          ships_to_refuel += [ship]
          @my_player.fuel_reserve -= ship.max_fuel - ship.current_fuel
        end
      end
    end

    unless ships_to_refuel.empty?
      puts "    refueling #{ships_to_refuel.size}"
      Resque.enqueue(RefuelShips, ships_to_refuel.collect(&:id))
    end
  end

  def deploy_travelling_ships
    # Expand to new planets based on tic
    if @travelling_ships.size < @number_of_travelling_ships
      (@number_of_travelling_ships - @travelling_ships.size).to_i.times do |i|
        planet_to_conquer = Planet.
          not_my_planets.
          select("id, POINT(location) <-> POINT('#{@home.location}') as distance, location").
          where("location::varchar NOT IN(SELECT destination::varchar FROM my_ships WHERE destination IS NOT NULL)").
          where("location::varchar NOT IN(SELECT location::varchar FROM my_ships WHERE name LIKE '%miner%')").
          order("distance").
          offset(i).first

        #expand_to_new_planet(next_expand_planet(i, @home))
        expand_to_new_planet(planet_to_conquer)
      end
    end
  end

  def deploy_armada_groups
    puts "Number of armada groups: #{@armada_ships.group_by(&:objective).size}"
    if @armada_ships.each_slice(@number_of_ships_in_armada).to_a.size < @number_of_armada_groups

      # For now only create 1 armada group because it takes too long
      #(@number_of_armada_groups - @armada_ships.each_slice(@number_of_ships_in_armada).to_a.size).times do |i|
      5.times do |i|
        # Create another group of amada ships if you can
        cost_of_attack_fleet = ((PriceList.ship) +
          (PriceList.defense * 200) +
          (PriceList.attack * 200) +
          (PriceList.prospecting * 20) +
          (PriceList.engineering * 80) +
          (Functions.get_numeric_variable('MAX_SHIP_FUEL') / 3) +
          (Functions.get_numeric_variable('MAX_SHIP_SPEED') / 3)
        ) * @number_of_ships_in_armada

        #puts "Attack fleet cost: #{cost_of_attack_fleet}"

        if @my_player.total_resources >= cost_of_attack_fleet
          #puts "Number of armada planets: #{@armada_planets.size}"
          #planet_to_conquer = @armada_planets.sort_by { |ap| Functions.distance_between(@home, ap) }.first
          planet_to_conquer = Planet.
            not_my_planets.
            select("id, POINT(location) <-> POINT('#{@home.location}') as distance, location").
            where("location::varchar NOT IN(SELECT destination::varchar FROM my_ships WHERE destination IS NOT NULL)").
            where("location::varchar NOT IN(SELECT location::varchar FROM my_ships WHERE name LIKE '%miner%')").
            order("distance").
            offset(i).first

          if planet_to_conquer

            #@my_player -= cost_of_attack_fleet
            closest_planet_to_objective = planet_to_conquer.closest_planets(1).my_planets.first
            @armadas_to_deploy << [closest_planet_to_objective.id, planet_to_conquer.id, @number_of_ships_in_armada]
            #Resque.enqueue(ArmadaShips, closest_planet_to_objective.id, planet_to_conquer.id, @number_of_ships_in_armada)
          end
        end
      end
    end
  end

  def upgrade_bad_travellers
    up_trav_ship_ids = @travelling_ships.select { |s| s.max_fuel < 100000 }.collect(&:id)
    unless up_trav_ship_ids.empty?
      @my_player.convert_fuel_to_money((PriceList.max_fuel * up_trav_ship_ids.size * 100000).to_i)
      MyShip.select("UPGRADE(id, 'MAX_FUEL', 100000)").where(:id => up_trav_ship_ids).all
    end

    up_trav_ship_ids = @travelling_ships.select { |s| s.max_speed < 100000 }.collect(&:id)
    unless up_trav_ship_ids.empty?
      @my_player.convert_fuel_to_money((PriceList.max_speed * up_trav_ship_ids.size * 100000).to_i)
      MyShip.select("UPGRADE(id, 'MAX_SPEED', 100000)").where(:id => up_trav_ship_ids).all
    end

    up_trav_ship_ids = @travelling_ships.select { |s| s.target_speed == 1000 && s.distance_from_objective > 1000 }.collect(&:id)
    unless up_trav_ship_ids.empty?
      MyShip.update_all({:target_speed => 400000}, {:id => up_trav_ship_ids})
    end

    up_trav_ship_ids = @armada_ships.select { |s| s.max_fuel < 100000 }.collect(&:id)
    unless up_trav_ship_ids.empty?
      @my_player.convert_fuel_to_money((PriceList.max_fuel * up_trav_ship_ids.size * 100000).to_i)
      MyShip.select("UPGRADE(id, 'MAX_FUEL', 100000)").where(:id => up_trav_ship_ids).all
    end

    up_trav_ship_ids = @armada_ships.select { |s| s.max_speed < 100000 }.collect(&:id)
    unless up_trav_ship_ids.empty?
      @my_player.convert_fuel_to_money((PriceList.max_speed * up_trav_ship_ids.size * 100000).to_i)
      MyShip.select("UPGRADE(id, 'MAX_SPEED', 100000)").where(:id => up_trav_ship_ids).all
    end

    up_trav_ship_ids = @armada_ships.select { |s| s.target_speed == 1000 && s.distance_from_objective > 1000 }.collect(&:id)
    unless up_trav_ship_ids.empty?
      MyShip.update_all({:target_speed => 400000}, {:id => up_trav_ship_ids})
    end

  end

  def manage_travelling_ships_actions
    # handle all travelling ships
    @travelling_ships.sort_by(&:distance_from_objective).each do |travelling_ship|
      begin
        if travelling_ship.at_destination?
          if travelling_ship.objective.is_a?(Planet)
            if @planets.include?(travelling_ship.objective) || travelling_ship.ships_in_range.size > 0
              puts "At planet #{travelling_ship.objective.name} => Ships in Range #{travelling_ship.ships_in_range.size}"
              # Lets move this ship to another planet!
              #new_planet = next_expand_planet(0, travelling_ship)
              new_planet = Planet.not_my_planets.
                select("id, POINT(location) <-> POINT('#{travelling_ship.objective.location}') as distance, location").
                where("location::varchar NOT IN(SELECT destination::varchar FROM my_ships WHERE destination IS NOT NULL)").
                where("location::varchar NOT IN(SELECT location::varchar FROM my_ships WHERE name LIKE '%miner%')").
                order("distance").first
              if travelling_ship.course_control(travelling_ship.max_speed, nil, new_planet.location)
                travelling_ship.objective = new_planet
                #@objective_planets.delete(new_planet)
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
            #travelling_ship.modify_speed(@ships)
            #travelling_ship.modify_fuel(@ships)
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
    puts "managing armada groups"
    @armada_ships.select { |s| !s.objective.nil? }.group_by(&:objective).each do |armada_ship_grp|
      begin
        #armada_ship_grp.last.each do |armada_ship|
        #  armada_ship.update_attributes(:action => "MINE", :action_target_id => armada_ship.objective.id)
        #end
        if armada_ship_grp.last.select { |as| as.at_destination? }.size > 0 || @planets.include?(armada_ship_grp.first)

          #armada_ship_grp.last.each do |armada_ship|
          #  armada_ship.update_attributes(:action => "MINE", :action_target_id => armada_ship.objective.id)
          #end

          if @planets.include?(armada_ship_grp.first)
            #new_armada_planet = @armada_planets.sort_by { |p| Functions.distance_between(p, armada_ship_grp.last[0]) }.first
            new_armada_planet = Planet.
              not_my_planets.
              select("id, name, POINT(location) <-> POINT('#{armada_ship_grp.first.location}') as distance, location").
              where("location::varchar NOT IN(SELECT destination::varchar FROM my_ships WHERE destination IS NOT NULL)").
              where("location::varchar NOT IN(SELECT location::varchar FROM my_ships WHERE name LIKE '%miner%')").
              order("distance").first

            if new_armada_planet
              puts "MISSION COMPLETE!! MOVE ON"
              puts "moving ships to #{new_armada_planet.name}"
              armada_ship_grp.last.each do |armada_ship|
                if armada_ship.course_control(armada_ship.max_speed, nil, new_armada_planet.location)
                  armada_ship.objective = new_armada_planet
                  armada_ship.update_attributes(:action => "MINE", :action_target_id => new_armada_planet.id)
                end
              end
              #@armada_planets.delete(new_armada_planet)
              #@armada_targets << new_armada_planet
            end
          end
        end
      rescue
      end
    end
  end

  def manage_ships_in_range
    puts "manage ships in range"
    enemy_ships = @ships_in_range.select { |s| !s.player_id.zero? }
    stashed_ships = @ships_in_range.select { |s| s.player_id.zero? }

    #enemy_ship_ids = enemy_ships.collect(&:ship_in_range_of)
    #stashed_ship_ids = stashed_ships.collect(&:ship_in_range_of)

    enemy_locations = enemy_ships.collect(&:enemy_location).uniq

    enemy_locations.each do |el|
      ships_to_pop = @trade_ships.select { |ss|
        d = Functions.distance_between_strs(ss.location, el)
        d < 300
      }
      #ships_to_pop = @trade_ships.select { |ss| ss.location.eql?(el) }
      unless ships_to_pop.empty?
        puts "    Need to pop #{ships_to_pop.size} to fight"

        free_up_ships(ships_to_pop.size)
        TradeItem.delete_trades(ships_to_pop.collect(&:id))
        @trade_ships = @trade_ships - ships_to_pop
        @ships = @ships + ships_to_pop
      end
    end


  end

  def handle_lost_planets
    @lost_planets.each do |lost_planet|
      pop_ships = @trade_ships.select { |ts| ts.location.eql?(lost_planet.location) }
      unless pop_ships.emtpy?
        free_up_ships(pop_ships.size)
        TradeItem.delete_trades(pop_ships.collect(&:id))
        @trades = @trades - pop_ships
        @ships = @ships + pop_ships
      end
    end

  end

  def attack_ships
    #puts "Checking for ships to attack"
    #attacking_ships = []
    #@ships_in_range.select { |s| !s.player_id.zero? }.each do |sir|
    #  next if attacking_ships.collect(&:id).include?(sir.ship_in_range_of)
    #  begin
    #    attack_ship = @ships.select { |s| s.id.eql?(sir.ship_in_range_of) && ["ATTACK"].include?(s.action.strip) }.first
    #    if attack_ship
    #      attacking_ships << attack_ship
    #      attack_ship.commence_attack(sir.id)
    #    end
    #  rescue
    #  end
    #end
    ShipsInRange.select("ATTACK(ships_in_range.ship_in_range_of, MIN(ships_in_range.id))").joins(:my_ship).where("my_ships.name NOT LIKE '%repairer%' AND my_ships.name NOT LIKE '%traveller%' AND my_ships.name NOT LIKE '%armada%'").group("ships_in_range.ship_in_range_of").all
    ShipsInRange.select("ATTACK(ships_in_range.ship_in_range_of, MIN(ships_in_range.id))").joins(:my_ship).where("my_ships.name LIKE '%traveller%' OR my_ships.name LIKE '%armada%'").group("ships_in_range.ship_in_range_of").all if @tic % 2 == 0
  end

  def repair_ships
    # Repair ships
    puts "Checking for ships to repair"
    repairing_ships = []
    @ships.select { |s| s.current_health < 100 }.each do |hurt_ship|
      begin

        repair_ship = @ships.detect { |s| Functions.distance_between(s, hurt_ship) <= s.range && !s.eql?(hurt_ship) && s.action.strip.eql?("REPAIR") && !repairing_ships.include?(s) }
        if repair_ship
          repair_ship.repair(hurt_ship.id)
          repairing_ships << repair_ship
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
      mining_gain_per_prospecting = 12.65
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
