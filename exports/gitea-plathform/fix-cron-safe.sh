
CRON_TMP=$(mktemp)

# ดึงของเดิมแบบ safe
crontab -l 2>/dev/null > "$CRON_TMP" || true

# ลบ job เดิม (กันซ้ำ)
sed -i '/zgitea-installer/d' "$CRON_TMP"

# ใส่ใหม่ (VALID 100%)
cat <<EOF >> "$CRON_TMP"

*/2 * * * * ${BASE_DIR}/ai-engine.sh # zgitea-installer
0 */6 * * * ${BASE_DIR}/backup.sh # zgitea-installer

EOF

# apply
crontab "$CRON_TMP"
rm -f "$CRON_TMP"
