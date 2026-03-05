#!/bin/bash

if [[ -t 1 ]]; then
    GREEN=$'\033[0;32m'
    YELLOW=$'\033[1;33m'
    RED=$'\033[0;31m'
    CYAN=$'\033[0;36m'
    NC=$'\033[0m'
else
    GREEN=""
    YELLOW=""
    RED=""
    CYAN=""
    NC=""
fi

print_header() {
    printf '%b\n' "${CYAN}______  ____________________________________________________${NC}"
    printf '%b\n' "${CYAN}___   |/  /___  _/_  ___/_  ___/___  _/__  __ \\___  _/__    |${NC}"
    printf '%b\n' "${CYAN}__  /|_/ / __  / _____ \\_____ \\ __  / __  /_/ /__  / __  /| |${NC}"
    printf '%b\n' "${CYAN}_  /  / / __/ /  ____/ /____/ /__/ /  _  _, _/__/ /  _  ___ |${NC}"
    printf '%b\n' "${CYAN}/_/  /_/  /___/  /____/ /____/ /___/  /_/ |_| /___/  /_/  |_|${NC}"
    printf '%b\n' "${CYAN}                                                             v2${NC}"
    printf '%b\n' "${GREEN}WP-CRON MASTER${NC}"
}

print_header

# 1. Parse Nginx configs for all active domain names
# This extracts server_name directives, splits multiple domains on the same line,
# removes semicolons, and filters out the default Nginx catch-all (_)
DOMAINS=$(grep -rsh "^\s*server_name" /etc/nginx/sites-enabled/ | sed 's/server_name//g' | tr -d ';' | tr -s ' ' '\n' | awk 'NF' | grep -v "^_$")

# 2. Loop through unique domains and hit their wp-cron.php endpoint
for DOMAIN in $(echo "$DOMAINS" | sort | uniq); do

    echo -e "${YELLOW}Pinging -> $DOMAIN${NC}"

    # We use cURL to hit the cron endpoint.
    # -s: Silent mode (no progress bar)
    # -L: Follow redirects (in case of HTTP to HTTPS redirects)
    # -m 30: Max execution time of 30 seconds so a hanging site doesn't freeze the script
    # -A: Custom User-Agent so you can identify this traffic in Nginx access logs

    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -L -m 30 -A "Missiria-Cron-Bot" "http://$DOMAIN/wp-cron.php?doing_wp_cron")

    if [ "$HTTP_STATUS" -eq 200 ]; then
        echo -e "${GREEN}✓ Cron triggered successfully (HTTP 200)${NC}"
    else
        echo -e "${RED}✗ Failed or Skipped (HTTP $HTTP_STATUS) - Ensure the domain resolves to this VPS.${NC}"
    fi

    # A short pause to let PHP-FPM spawn and kill workers smoothly without spiking CPU
    sleep 2
done

echo -e "\n${GREEN}======================================================${NC}"
echo -e "${GREEN} All background update queues have been triggered!    ${NC}"
echo -e "${GREEN}======================================================${NC}"
