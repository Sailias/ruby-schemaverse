class TravellingShip < MyShip

  attr_accessor :queue

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

  def process_queue
    next_objective = queue.first
    if explorer_ship.course_control(Functions.distance_between(self, next_objective) / 2, nil, next_objective)
      self.objective = next_objective
      queue.shift
    end
  end

end