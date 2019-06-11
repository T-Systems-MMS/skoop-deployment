#!/usr/bin/env bash

# Create or update SKOOP deployment.

if [ -z "$SERVER_DOMAIN" ]; then
  echo "WARNING: Environment variable SERVER_DOMAIN is not defined. Default domain 'localhost' will be used."
fi

# docker-compose -p skoop up -d
docker stack rm skoop
sleep 30
docker stack deploy --compose-file docker-compose.yml skoop
