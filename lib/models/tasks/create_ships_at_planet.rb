class CreateShipsAtPlanet
  @queue = :ships

  def self.perform(planet_id, miners, defenders, repairers)
    planet = Planet.find planet_id
    MyShip.create_ships_at(miners, planet, 'miner', 480, 0, 0, 0, 'MINE', planet_id) if miners > 0
    MyShip.create_ships_at(defenders, planet, 'defender', 0, 200, 200, 80, 'ATTACK', nil) if defenders > 0
    MyShip.create_ships_at(repairers, planet, 'repairer', 0, 0, 200, 280, 'ATTACK', nil) if repairers > 0
  end
end