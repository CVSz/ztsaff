#!/usr/bin/env bash
tar -czf snapshot-$(date +%F).tar.gz docker-compose.yml Caddyfile
