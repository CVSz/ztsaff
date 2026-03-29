
mkdir -p "${BASE_DIR}/monitoring"

cat > "${BASE_DIR}/monitoring/prometheus.yml" <<'EOF'
global:
  scrape_interval: 5s

scrape_configs:
  - job_name: node
    static_configs:
      - targets: ['node-exporter:9100']

  - job_name: cadvisor
    static_configs:
      - targets: ['cadvisor:8080']
EOF
