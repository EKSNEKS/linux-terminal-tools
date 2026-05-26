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

# --- POSTFIX VIRTUAL_ALIAS_DOMAINS ---
echo -e "\n📡 [POSTFIX VIRTUAL_ALIAS_DOMAINS]"
if postconf virtual_alias_domains 2>/dev/null | grep -qw "$DOMAIN"; then
    echo "✅ DOMAIN IN virtual_alias_domains: FOUND"
else
    echo "❌ DOMAIN IN virtual_alias_domains: MISSING"
    echo "   👉 FIX: postconf -e \"virtual_alias_domains = \$(postconf -h virtual_alias_domains), $DOMAIN\" && postfix reload"
fi

# --- POSTFIX virtual.db FRESHNESS ---
echo -e "\n🗄️  [POSTFIX VIRTUAL DB (postmap)]"
VIRTUAL_FILE="/etc/postfix/virtual"
VIRTUAL_DB="/etc/postfix/virtual.db"
if [ -f "$VIRTUAL_DB" ]; then
    V_SRC_MT=$(stat -c '%Y' "$VIRTUAL_FILE" 2>/dev/null)
    V_DB_MT=$(stat -c '%Y' "$VIRTUAL_DB" 2>/dev/null)
    if [ "$V_DB_MT" -ge "$V_SRC_MT" ]; then
        echo "✅ virtual.db UP TO DATE"
    else
        echo "❌ virtual.db STALE (older than /etc/postfix/virtual)"
        echo "   👉 FIX: postmap /etc/postfix/virtual && postfix reload"
    fi
    # Also verify alias resolves in the DB
    if postmap -q "$EMAIL" hash:"$VIRTUAL_FILE" &>/dev/null; then
        RESOLVED=$(postmap -q "$EMAIL" hash:"$VIRTUAL_FILE")
        echo "✅ ALIAS DB LOOKUP: $EMAIL → $RESOLVED"
    else
        echo "❌ ALIAS DB LOOKUP: $EMAIL not found in virtual.db"
        echo "   👉 FIX: grep '$EMAIL' $VIRTUAL_FILE — add if missing, then postmap $VIRTUAL_FILE"
    fi
else
    echo "❌ virtual.db MISSING"
    echo "   👉 FIX: postmap /etc/postfix/virtual && postfix reload"
fi

# --- POSTFIX RELOAD STATUS ---
echo -e "\n🔄 [POSTFIX RELOAD STATUS]"
MAINCF_MT=$(stat -c '%Y' /etc/postfix/main.cf 2>/dev/null)
POSTFIX_START=$(systemctl show postfix --property=ExecMainStartTimestamp 2>/dev/null | cut -d= -f2)
if [ -n "$POSTFIX_START" ]; then
    POSTFIX_START_EPOCH=$(date -d "$POSTFIX_START" +%s 2>/dev/null)
    if [ -n "$POSTFIX_START_EPOCH" ] && [ -n "$MAINCF_MT" ]; then
        if [ "$MAINCF_MT" -gt "$POSTFIX_START_EPOCH" ]; then
            echo "⚠️  main.cf MODIFIED AFTER LAST POSTFIX START — reload needed"
            echo "   👉 FIX: postfix reload"
        else
            echo "✅ POSTFIX CONFIG LOADED (main.cf older than service start)"
        fi
    fi
else
    echo "⚠️  Could not determine Postfix start time"
fi

# --- DOVECOT USERS ---
echo -e "\n🔐 [DOVECOT PASSWD-FILE]"
if grep -q "^${EMAIL}:" /etc/dovecot/users 2>/dev/null; then
    echo "✅ DOVECOT ENTRY: FOUND"
    if [ "$(stat -c '%G' /etc/dovecot/users)" = "dovecot" ]; then
        echo "✅ DOVECOT USERS PERMISSIONS: OK (root:dovecot)"
    else
        echo "❌ DOVECOT USERS PERMISSIONS: WRONG (not root:dovecot)"
        echo "   👉 FIX: chown root:dovecot /etc/dovecot/users && chmod 0640 /etc/dovecot/users"
    fi
else
    echo "❌ DOVECOT ENTRY: MISSING"
    echo "   👉 FIX: add entry to /etc/dovecot/users or run create_email $DOMAIN $USER_PREFIX"
fi

# --- MX RECORD ---
echo -e "\n🌐 [DNS MX RECORD]"
MX_RECORD=$(dig +short MX "$DOMAIN" 2>/dev/null | head -1)
if [[ "$MX_RECORD" == *"mail.eksneks.com"* ]]; then
    echo "✅ MX RECORD: $MX_RECORD"
elif [[ -n "$MX_RECORD" ]]; then
    echo "⚠️  MX RECORD: $MX_RECORD (not pointing to mail.eksneks.com)"
else
    echo "❌ MX RECORD: MISSING"
    echo "   👉 FIX: Add in DNS/Cloudflare → MX $DOMAIN → mail.eksneks.com (priority 10)"
fi
echo "------------------------------------------------"

# --- SPF RECORD ---
echo -e "\n🛡️  [DNS SPF RECORD]"
SPF_RECORD=$(dig +short TXT "$DOMAIN" 2>/dev/null | grep "v=spf1" | tr -d '"')
if [[ "$SPF_RECORD" == *"ip4:$SERVER_IP"* ]]; then
    echo "✅ SPF RECORD: $SPF_RECORD"
elif [[ -n "$SPF_RECORD" ]]; then
    echo "⚠️  SPF FOUND but ip4:$SERVER_IP missing: $SPF_RECORD"
    echo "   👉 FIX: Edit DNS TXT record to include ip4:$SERVER_IP"
else
    echo "❌ SPF RECORD: MISSING"
    echo "   👉 FIX: Add DNS TXT → \"v=spf1 ip4:$SERVER_IP mx ~all\""
fi

# --- DKIM ---
echo -e "\n🔑 [DKIM]"
DKIM_KEY_FILE="/etc/opendkim/keys/$DOMAIN/mail.private"
DKIM_TXT_FILE="/etc/opendkim/keys/$DOMAIN/mail.txt"
if [ -f "$DKIM_KEY_FILE" ]; then
    echo "✅ DKIM KEY FILE: $DKIM_KEY_FILE"
else
    echo "❌ DKIM KEY FILE MISSING: $DKIM_KEY_FILE"
    echo "   👉 FIX: mkdir -p /etc/opendkim/keys/$DOMAIN && opendkim-genkey -s mail -d $DOMAIN -D /etc/opendkim/keys/$DOMAIN && chown -R opendkim:opendkim /etc/opendkim/keys/$DOMAIN"
fi

if grep -q "mail._domainkey.$DOMAIN" /etc/opendkim/KeyTable 2>/dev/null; then
    echo "✅ OPENDKIM KeyTable: FOUND"
else
    echo "❌ OPENDKIM KeyTable: MISSING"
    echo "   👉 FIX: echo \"mail._domainkey.$DOMAIN $DOMAIN:mail:/etc/opendkim/keys/$DOMAIN/mail.private\" >> /etc/opendkim/KeyTable"
fi

if grep -q "$EMAIL\|@$DOMAIN" /etc/opendkim/SigningTable 2>/dev/null; then
    echo "✅ OPENDKIM SigningTable: FOUND"
else
    echo "❌ OPENDKIM SigningTable: MISSING"
    echo "   👉 FIX: echo \"*@$DOMAIN mail._domainkey.$DOMAIN\" >> /etc/opendkim/SigningTable && systemctl reload opendkim"
fi

DKIM_DNS=$(dig +short TXT "mail._domainkey.$DOMAIN" 2>/dev/null | tr -d '"' | tr -d ' ')
if [[ "$DKIM_DNS" == *"v=DKIM1"* ]]; then
    echo "✅ DKIM DNS RECORD: PUBLISHED"
else
    echo "❌ DKIM DNS RECORD: NOT PUBLISHED (mail._domainkey.$DOMAIN)"
    if [ -f "$DKIM_TXT_FILE" ]; then
        echo "   👉 Key to publish (add as TXT record in Cloudflare/DNS):"
        echo "      Name: mail._domainkey"
        grep -oP '"p=[^"]*"' "$DKIM_TXT_FILE" | head -3 | sed 's/^/      /'
        echo "      Full record: cat $DKIM_TXT_FILE"
    fi
fi

# --- DMARC ---
echo -e "\n📋 [DNS DMARC RECORD]"
DMARC_RECORD=$(dig +short TXT "_dmarc.$DOMAIN" 2>/dev/null | tr -d '"')
if [[ "$DMARC_RECORD" == *"v=DMARC1"* ]]; then
    echo "✅ DMARC RECORD: $DMARC_RECORD"
else
    echo "❌ DMARC RECORD: MISSING (_dmarc.$DOMAIN)"
    echo "   👉 FIX: Add DNS TXT → \"v=DMARC1; p=none; rua=mailto:dmarc-reports@$DOMAIN; pct=100\""
fi

# --- RECENT REJECTIONS ---
echo -e "\n🚫 [RECENT INBOUND REJECTIONS (last 48h)]"
REJECTS=$(grep "to=<$EMAIL>" /var/log/mail.log /var/log/mail.log.1 2>/dev/null | grep -i "Relay access denied\|reject\|NOQUEUE" | tail -10)
if [ -n "$REJECTS" ]; then
    echo "⚠️  RECENT REJECTIONS FOUND:"
    echo "$REJECTS" | while IFS= read -r line; do
        echo "   $line"
    done
    echo ""
    echo "   ⚠️  If senders got 554 permanent reject, they will NOT retry."
    echo "   👉 ACTION: Request resend from those senders (Facebook/Google/etc resend verification)."
else
    echo "✅ NO RECENT REJECTIONS in mail.log"
fi

# --- DEFERRED QUEUE ---
echo -e "\n📬 [POSTFIX DEFERRED QUEUE for $DOMAIN]"
QUEUE_HITS=$(postqueue -p 2>/dev/null | grep -A3 "$DOMAIN")
if [ -n "$QUEUE_HITS" ]; then
    echo "⚠️  MESSAGES IN QUEUE:"
    echo "$QUEUE_HITS"
else
    echo "✅ NO DEFERRED MESSAGES for $DOMAIN"
fi

echo "------------------------------------------------"
