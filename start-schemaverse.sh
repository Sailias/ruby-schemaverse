cd ~/apps/ruby-schemaverse
~/Downloads/redis-2.2.11/src/redis-server &
QUEUES=stash_ships,ships,refuel,moving,unstash_ships rake resque:work &
