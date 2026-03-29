#!/usr/bin/env bash
for c in $(docker ps -q); do
  docker inspect --format '{{.State.Running}}' $c | grep true || docker restart $c
done
