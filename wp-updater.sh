#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN} 🚀 ULTIMATE WP UPGRADER (CORE + PLUGINS + THEMES)   ${NC}"
echo -e "${GREEN}======================================================${NC}"

WP_CONFIGS=$(find /var/www/ -name "wp-config.php" -type f 2>/dev/null)

for CONFIG in $WP_CONFIGS; do
    SITE_PATH=$(dirname "$CONFIG")
    DOMAIN=""

    # 1. Detect Domain
    NGINX_CONF=$(grep -Rl "$SITE_PATH" /etc/nginx/sites-enabled/ 2>/dev/null | head -n 1)
    if [ -n "$NGINX_CONF" ]; then
        DOMAIN=$(grep -E "^\s*server_name" "$NGINX_CONF" | head -n 1 | awk '{print $2}' | tr -d ';')
    fi

    if [ -z "$DOMAIN" ] || [ "$DOMAIN" == "_" ]; then continue; fi

    # 2. FEATURE: DEAD SITE DETECTION
    HTTP_STATUS=$(curl -o /dev/null -s -w "%{http_code}" -L -m 5 "http://$DOMAIN")
    if [ "$HTTP_STATUS" -eq 000 ] || [ "$HTTP_STATUS" -ge 500 ]; then
        echo -e "${RED}DEAD SITE -> $DOMAIN (Status: $HTTP_STATUS). Skipping.${NC}"
        continue
    fi

    echo -e "\n${YELLOW}Processing -> $DOMAIN${NC}"

    # 3. PHP PAYLOAD
    cat << 'EOF' > "$SITE_PATH/missiria-trigger.php"
<?php
define('FS_METHOD', 'direct');
define('WP_USE_THEMES', false);
set_time_limit(600);

require('./wp-load.php');
require_once(ABSPATH . 'wp-admin/includes/admin.php');
require_once(ABSPATH . 'wp-admin/includes/file.php');
require_once(ABSPATH . 'wp-admin/includes/class-wp-upgrader.php');

$skin = new Automatic_Upgrader_Skin();

// Force Check
wp_clean_update_cache();
wp_version_check();
wp_update_plugins();

// A. CORE
$core = get_core_updates();
if (isset($core[0]) && $core[0]->response == 'upgrade') {
    $cu = new Core_Upgrader($skin);
    $cu->upgrade($core[0]);
}

// B. PLUGINS
$up = get_site_transient('update_plugins');
if (!empty($up->response)) {
    $pu = new Plugin_Upgrader($skin);
    $pu->bulk_upgrade(array_keys($up->response));
}

// C. LANGUAGES
$lp = wp_get_translation_updates();
if (!empty($lp)) {
    $lu = new Language_Pack_Upgrader($skin);
    $lu->bulk_upgrade($lp);
}

echo "TRIGGER_FINISHED_OK";
EOF

    chown www-data:www-data "$SITE_PATH/missiria-trigger.php"

    # 4. RUN & CHECK (Accepts 'OK' or 'TRIGGER_FINISHED_OK')
    HTTP_RESP=$(curl -s -L -m 600 "http://$DOMAIN/missiria-trigger.php")

    if [[ "$HTTP_RESP" == *"OK"* ]]; then
        echo -e "${GREEN}✓ SUCCESS on $DOMAIN!${NC}"
    else
        echo -e "${RED}✗ ACTUAL FAIL on $DOMAIN. Response: $HTTP_RESP${NC}"
    fi

    rm -f "$SITE_PATH/missiria-trigger.php"
done

echo -e "\n${GREEN}======================================================${NC}"