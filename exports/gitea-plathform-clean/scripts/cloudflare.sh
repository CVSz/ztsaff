#!/usr/bin/env bash
docker run -d \
  --name cf \
  --restart unless-stopped \
  cloudflare/cloudflared \
  tunnel run --token $CF_TOKEN
