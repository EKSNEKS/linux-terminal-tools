#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN} 🚀 MASTER WP UPGRADER: DETAILED LOGGING MODE        ${NC}"
echo -e "${GREEN}======================================================${NC}"

# Start Global Timer
GLOBAL_START=$(date +%s)

WP_CONFIGS=$(find /var/www/ -name "wp-config.php" -type f 2>/dev/null)

for CONFIG in $WP_CONFIGS; do
    SITE_START=$(date +%s)
    SITE_PATH=$(dirname "$CONFIG")
    DOMAIN=""

    # 1. Detect Domain
    NGINX_CONF=$(grep -Rl "$SITE_PATH" /etc/nginx/sites-enabled/ 2>/dev/null | head -n 1)
    if [ -n "$NGINX_CONF" ]; then
        DOMAIN=$(grep -E "^\s*server_name" "$NGINX_CONF" | head -n 1 | awk '{print $2}' | tr -d ';')
    fi

    if [ -z "$DOMAIN" ] || [ "$DOMAIN" == "_" ]; then
        echo -e "${RED}[SKIP] No Nginx config for: $SITE_PATH${NC}"
        continue
    fi

    # 2. DEAD SITE DETECTION
    HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" -L -m 5 "http://$DOMAIN")
    if [ "$HTTP_STATUS" -eq 000 ] || [ "$HTTP_STATUS" -ge 500 ]; then
        echo -e "${RED}[DEAD] $DOMAIN (Status: $HTTP_STATUS). Skipping.${NC}"
        continue
    fi

    echo -e "\n${YELLOW}▶ Processing: $DOMAIN${NC}"

    # 3. ADVANCED PHP PAYLOAD
    cat << 'EOF' > "$SITE_PATH/missiria-trigger.php"
<?php
define('FS_METHOD', 'direct');
define('WP_USE_THEMES', false);
set_time_limit(900);

require('./wp-load.php');
require_once(ABSPATH . 'wp-admin/includes/admin.php');
require_once(ABSPATH . 'wp-admin/includes/file.php');
require_once(ABSPATH . 'wp-admin/includes/class-wp-upgrader.php');

$skin = new Automatic_Upgrader_Skin();
$logs = [];

// Clean Transients
delete_site_transient('update_core');
delete_site_transient('update_plugins');
wp_clean_update_cache();

// A. CORE
wp_version_check();
$core = get_core_updates();
if (isset($core[0]) && $core[0]->response == 'upgrade') {
    $old_v = $GLOBALS['wp_version'];
    $cu = new Core_Upgrader($skin);
    $result = $cu->upgrade($core[0]);
    include(ABSPATH . WPINC . '/version.php');
    $logs[] = "Core: $old_v -> $wp_version";
} else {
    $logs[] = "Core: Up-to-date";
}

// B. PLUGINS
wp_update_plugins();
$up = get_site_transient('update_plugins');
if (!empty($up->response)) {
    $count = count($up->response);
    $pu = new Plugin_Upgrader($skin);
    $pu->bulk_upgrade(array_keys($up->response));
    $logs[] = "Plugins: $count updated";
} else {
    $logs[] = "Plugins: 0 updates";
}

// C. LANGUAGES
$lp = wp_get_translation_updates();
if (!empty($lp)) {
    $lu = new Language_Pack_Upgrader($skin);
    $lu->bulk_upgrade($lp);
    $logs[] = "Languages: Done";
}

echo "LOG_DATA: " . implode(' | ', $logs);
EOF

    chown www-data:www-data "$SITE_PATH/missiria-trigger.php"

    # 4. EXECUTE & TIME
    HTTP_RESP=$(curl -s -L -m 900 "http://$DOMAIN/missiria-trigger.php")

    SITE_END=$(date +%s)
    DURATION=$((SITE_END - SITE_START))

    if [[ "$HTTP_RESP" == *"LOG_DATA"* ]]; then
        # Clean up the response to show only the log part
        CLEAN_LOG=$(echo "$HTTP_RESP" | grep -o "LOG_DATA:.*")
        echo -e "${GREEN}✓ DONE in ${DURATION}s | $CLEAN_LOG${NC}"
    else
        echo -e "${RED}✗ FAIL in ${DURATION}s | Response: $HTTP_RESP${NC}"
    fi

    rm -f "$SITE_PATH/missiria-trigger.php"
done

GLOBAL_END=$(date +%s)
TOTAL_TIME=$((GLOBAL_END - GLOBAL_START))

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN} ✅ ALL SITES FINISHED IN ${TOTAL_TIME} SECONDS          ${NC}"
echo -e "${GREEN}======================================================${NC}"