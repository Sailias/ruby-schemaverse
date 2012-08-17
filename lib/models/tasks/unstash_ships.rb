class UnstashShips
  @queue = :unstash_ships

  def self.perform
    TradeItem.destroy_all_trades
  end
end