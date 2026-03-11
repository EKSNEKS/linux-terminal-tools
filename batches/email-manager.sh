#!/bin/bash
# 🛠️ THE ULTIMATE EMAIL AUDIT - THE "MISSIRIA" VERSION (FINAL FIX)
# Usage: ./audit_email.sh contact@sabrina-missiria-group.com

if [[ -t 1 ]]; then
    GREEN=$'\033[0;32m'
    CYAN=$'\033[0;36m'
    NC=$'\033[0m'
else
    GREEN=""
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
    printf '%b\n' "${GREEN}EMAIL MANAGER${NC}"
}

EMAIL=$1
SERVER_IP="81.17.98.31"

print_header

if [ -z "$EMAIL" ]; then
    echo "Usage: ./email-manager.sh user@domain.com"
    exit 1
fi

# --- THE MISSIRIA NAMING LOGIC ---
# 1. Get prefix (contact)
USER_PREFIX=$(echo "$EMAIL" | cut -d'@' -f1)

# 2. Get domain (sabrina-missiria-group.com)
DOMAIN=$(echo "$EMAIL" | cut -d'@' -f2)

# 3. Get site name (sabrina-missiria-group)
SITE_NAME=$(echo "$DOMAIN" | cut -d'.' -f1)

# 4. Convert ALL dashes to underscores (sabrina_missiria_group)
SITE_CLEAN=$(echo "$SITE_NAME" | tr '-' '_')

# 5. Result: contact_sabrina_missiria_group
FULL_USER="${USER_PREFIX}_${SITE_CLEAN}"

echo "------------------------------------------------"
echo -e "🔍 AUDITING: \033[1;34m$EMAIL\033[0m"
echo -e "👤 SYSTEM USER: \033[1;32m$FULL_USER\033[0m"
echo "------------------------------------------------"

# --- INTERNAL SERVER CONFIG ---
echo -e "⚙️  [INTERNAL SERVER CONFIG]"
if grep -q "$EMAIL" /etc/postfix/virtual; then
    echo "✅ POSTFIX ALIAS: FOUND"
else
    echo "❌ POSTFIX ALIAS: MISSING"
    echo "   👉 INSTRUCTION: echo \"$EMAIL $FULL_USER\" | sudo tee -a /etc/postfix/virtual && sudo postmap /etc/postfix/virtual"
fi

# --- STORAGE & PERMISSIONS ---
echo -e "\n📂 [STORAGE & PERMISSIONS]"
HOME_DIR="/home/$FULL_USER"
MAILDIR="$HOME_DIR/Maildir"



if [ -d "$MAILDIR" ]; then
    # Get the current actual owner from the system
    CURRENT_OWNER=$(stat -c "%U:%G" "$MAILDIR")
    
    if [ "$CURRENT_OWNER" == "$FULL_USER:$FULL_USER" ]; then
        echo -e "✅ PERMISSIONS: PASS (\033[0;32m$CURRENT_OWNER\033[0m)"
    else
        echo -e "❌ PERMISSIONS: \033[0;31mWRONG ($CURRENT_OWNER)\033[0m"
        # THE FIX: This now uses the SAME variable as the check
        echo "   👉 INSTRUCTION: sudo chown -R $FULL_USER:$FULL_USER $HOME_DIR"
    fi
else
    echo -e "❌ MAILDIR: \033[0;31mNOT FOUND\033[0m"
    echo "   👉 INSTRUCTION: sudo mkdir -p $MAILDIR/{cur,new,tmp} && sudo chown -R $FULL_USER:$FULL_USER $HOME_DIR"
fi
echo "------------------------------------------------"
