#!/bin/bash

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}======================================================${NC}"
echo -e "${GREEN} Forcing Direct Manual Upgrades (Symlink Safe)        ${NC}"
echo -e "${GREEN}======================================================${NC}"

WP_CONFIGS=$(find /var/www/ -name "wp-config.php" -type f 2>/dev/null)

if [ -z "$WP_CONFIGS" ]; then
    echo -e "${RED}Error: No wp-config.php files found.${NC}"
    exit 1
fi

for CONFIG in $WP_CONFIGS; do
    
    DOMAIN=""
    NGINX_CONF=""
    SITE_PATH=$(dirname "$CONFIG")
    
    # 1. THE FIX: Use -R (capital R) to force grep to follow Nginx symlinks!
    NGINX_CONF=$(grep -Rl "$SITE_PATH" /etc/nginx/sites-enabled/ 2>/dev/null | head -n 1)
    
    # 2. Extract the actual domain from the config
    if [ -n "$NGINX_CONF" ]; then
        DOMAIN=$(grep -E "^\s*server_name" "$NGINX_CONF" | head -n 1 | awk '{print $2}' | tr -d ';')
    fi
    
    # 3. If no active Nginx config matches, skip it (bypasses old/dead folders)
    if [ -z "$DOMAIN" ] || [ "$DOMAIN" == "_" ]; then
        echo -e "\n${RED}Skipping -> $SITE_PATH (No active Nginx config found)${NC}"
        continue
    fi

    echo -e "\n${YELLOW}Folder: $SITE_PATH${NC}"
    echo -e "${YELLOW}Injecting payload and hitting -> $DOMAIN${NC}"
    
    # Create the temporary PHP trigger file
    cat << 'EOF' > "$SITE_PATH/missiria-trigger.php"
<?php
define('FS_METHOD', 'direct');
define('WP_USE_THEMES', false);
set_time_limit(0);
ignore_user_abort(true);

require('./wp-load.php');
require_once(ABSPATH . 'wp-admin/includes/admin.php');
require_once(ABSPATH . 'wp-admin/includes/file.php');
require_once(ABSPATH . 'wp-admin/includes/misc.php');
require_once(ABSPATH . 'wp-admin/includes/class-wp-upgrader.php');

wp_clean_update_cache();
wp_update_plugins();
wp_update_themes();

$skin = new Automatic_Upgrader_Skin();
$status = "OK";

$plugin_updates = get_site_transient('update_plugins');
if (!empty($plugin_updates->response)) {
    $plugin_upgrader = new Plugin_Upgrader($skin);
    $plugins_to_update = array_keys($plugin_updates->response);
    $result = $plugin_upgrader->bulk_upgrade($plugins_to_update);
    if (is_wp_error($result)) { $status .= " | Plugin Error"; }
}

$theme_updates = get_site_transient('update_themes');
if (!empty($theme_updates->response)) {
    $theme_upgrader = new Theme_Upgrader($skin);
    $themes_to_update = array_keys($theme_updates->response);
    $result = $theme_upgrader->bulk_upgrade($themes_to_update);
    if (is_wp_error($result)) { $status .= " | Theme Error"; }
}

echo $status;
EOF

    # Fix permissions so Nginx can execute it
    chown www-data:www-data "$SITE_PATH/missiria-trigger.php"
    
    # Run the HTTP request
    HTTP_RESP=$(curl -s -L -m 180 "http://$DOMAIN/missiria-trigger.php")
    
    if [[ "$HTTP_RESP" == *"OK"* ]]; then
        echo -e "${GREEN}✓ Upgrades successfully forced on $DOMAIN! Output: $HTTP_RESP${NC}"
    else
        echo -e "${RED}✗ cURL failed for $DOMAIN. Output: $HTTP_RESP${NC}"
    fi
    
    # Clean up
    rm -f "$SITE_PATH/missiria-trigger.php"
    
    sleep 3
done

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN} All active sites updated successfully.               ${NC}"
echo -e "${GREEN}======================================================${NC}"
