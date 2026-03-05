#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m❌ Please run as root (or use sudo).\033[0m"
    exit 1
fi

# Terminal Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- HELPER FUNCTIONS ---

update_domain() {
    DOMAIN=$1
    AVAIL="/etc/nginx/sites-available/$DOMAIN"
    ENABLED="/etc/nginx/sites-enabled/$DOMAIN"

    if [ ! -f "$AVAIL" ]; then
        echo -e "${RED}❌ Error: Configuration for $DOMAIN not found in sites-available.${NC}"
        return
    fi

    if [ -L "$ENABLED" ] || [ -f "$ENABLED" ]; then
        echo -e "${CYAN}🔄 Refreshing existing link for $DOMAIN...${NC}"
        rm "$ENABLED"
    fi

    ln -s "$AVAIL" "$ENABLED"
    echo -e "${GREEN}✅ Symlink created for $DOMAIN.${NC}"

    echo "Testing Nginx configuration..."
    if nginx -t; then
        systemctl reload nginx
        echo -e "${GREEN}🚀 SUCCESS: $DOMAIN is now live and Nginx reloaded!${NC}"
    else
        echo -e "${RED}⚠️ CRITICAL: Nginx config test failed. Reverting link...${NC}"
        rm "$ENABLED"
    fi
}

delete_domain() {
    DOMAIN=$1
    AVAIL="/etc/nginx/sites-available/$DOMAIN"
    ENABLED="/etc/nginx/sites-enabled/$DOMAIN"

    echo -e "${CYAN}🔄 Removing existing links and configs for $DOMAIN...${NC}"

    if [ -L "$ENABLED" ]; then
        rm "$ENABLED"
        echo -e "${GREEN}✅ Symlink removed for $DOMAIN.${NC}"
    else
        echo -e "${YELLOW}⚠️ No symlink found in sites-enabled.${NC}"
    fi

    if [ -f "$AVAIL" ]; then
        rm "$AVAIL"
        echo -e "${GREEN}✅ Configuration file deleted from sites-available.${NC}"
    else
        echo -e "${YELLOW}⚠️ No config file found in sites-available.${NC}"
    fi

    echo "Testing Nginx configuration..."
    if nginx -t; then
        systemctl reload nginx
        echo -e "${GREEN}🚀 SUCCESS: $DOMAIN has been removed and Nginx reloaded!${NC}"
    else
        echo -e "${RED}❌ ERROR: Nginx configuration test failed. Reload aborted.${NC}"
    fi
}

insert_domain() {
    DOMAIN=$1
    read -p "Enter the web root directory (Default: /var/www/MISSIRIA/$DOMAIN): " WEB_ROOT
    WEB_ROOT=${WEB_ROOT:-/var/www/MISSIRIA/$DOMAIN}

    AVAIL="/etc/nginx/sites-available/$DOMAIN"

    if [ -f "$AVAIL" ]; then
        echo -e "${RED}❌ Error: A configuration for $DOMAIN already exists!${NC}"
        return
    fi

    echo -e "${CYAN}📁 Creating directory $WEB_ROOT...${NC}"
    mkdir -p "$WEB_ROOT"
    chown -R www-data:www-data "$WEB_ROOT"
    chmod -R 755 "$WEB_ROOT"

    echo -e "${CYAN}📝 Generating Nginx configuration for WordPress/PHP...${NC}"
    
    cat > "$AVAIL" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN www.$DOMAIN;
    root $WEB_ROOT;
    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$args;
    }

    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock; # Adjust PHP version if necessary
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

    echo -e "${GREEN}✅ Nginx configuration generated at $AVAIL${NC}"
    
    # Automatically update/link the newly created domain
    update_domain "$DOMAIN"
}

# --- MAIN MENU UI ---

clear
echo -e "${BLUE}=================================================================${NC}"
echo -e "${BLUE}               NGINX MASTER MANAGER (nx-manager)                 ${NC}"
echo -e "${BLUE}=================================================================${NC}"
echo "1) Update / Reload Server Nginx (Synginx)"
echo "2) Delete Server Nginx (Delginx)"
echo "3) Insert / Create New Domain"
echo "4) Exit"
echo -e "${BLUE}=================================================================${NC}"
read -p "Select an option [1-4]: " OPTION

case $OPTION in
    1)
        read -p "Enter the domain to UPDATE: " INPUT_DOMAIN
        [[ -n "$INPUT_DOMAIN" ]] && update_domain "$INPUT_DOMAIN" || echo -e "${RED}Domain required.${NC}"
        ;;
    2)
        read -p "Enter the domain to DELETE: " INPUT_DOMAIN
        [[ -n "$INPUT_DOMAIN" ]] && delete_domain "$INPUT_DOMAIN" || echo -e "${RED}Domain required.${NC}"
        ;;
    3)
        read -p "Enter the NEW domain to INSERT: " INPUT_DOMAIN
        [[ -n "$INPUT_DOMAIN" ]] && insert_domain "$INPUT_DOMAIN" || echo -e "${RED}Domain required.${NC}"
        ;;
    4)
        echo -e "${GREEN}Exiting...${NC}"
        exit 0
        ;;
    *)
        echo -e "${RED}❌ Invalid option. Exiting.${NC}"
        exit 1
        ;;
esac
