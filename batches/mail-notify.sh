#!/bin/bash
# mail-notify.sh
# Watches Maildir/new/ for ALL accounts in /etc/dovecot/users.
# Sends Gmail alert when new mail arrives. Cron: every 5 min as root.

NOTIFY_TO="missiria@gmail.com"
NOTIFY_FROM="contact@eksneks.com"
SENDMAIL="/usr/sbin/sendmail"
USERS_FILE="/etc/dovecot/users"
STATE_DIR="/var/lib/missiria/mail-notify"
mkdir -p "$STATE_DIR"

while IFS=: read -r EMAIL _ _ _ _ HOME _; do
    [[ -z "$EMAIL" || "$EMAIL" == \#* ]] && continue

    MAILDIR="$HOME/Maildir/new"
    [[ ! -d "$MAILDIR" ]] && continue

    DOMAIN="${EMAIL#*@}"
    WEBMAIL="https://www.${DOMAIN}/webmail/"
    SAFE="${EMAIL//@/_at_}"
    SEEN_FILE="$STATE_DIR/${SAFE}.seen"

    touch "$SEEN_FILE"

    # Find emails not yet in seen file
    NEW_FILES=()
    while IFS= read -r fname; do
        [[ -z "$fname" ]] && continue
        if ! grep -qF "$fname" "$SEEN_FILE"; then
            NEW_FILES+=("$fname")
        fi
    done < <(ls "$MAILDIR" 2>/dev/null)

    if [[ ${#NEW_FILES[@]} -gt 0 ]]; then
        COUNT=${#NEW_FILES[@]}

        # Build subject list for email body
        SUBJECT_LIST=""
        for f in "${NEW_FILES[@]}"; do
            MAIL_FILE="$MAILDIR/$f"
            FROM_HDR=$(grep -m1 "^From:" "$MAIL_FILE" 2>/dev/null | sed 's/^From:[[:space:]]*//')
            SUBJ_HDR=$(grep -m1 "^Subject:" "$MAIL_FILE" 2>/dev/null | sed 's/^Subject:[[:space:]]*//')
            DATE_HDR=$(grep -m1 "^Date:" "$MAIL_FILE" 2>/dev/null | sed 's/^Date:[[:space:]]*//')
            [[ -z "$FROM_HDR" ]]  && FROM_HDR="(unknown sender)"
            [[ -z "$SUBJ_HDR" ]] && SUBJ_HDR="(no subject)"
            [[ -z "$DATE_HDR" ]]  && DATE_HDR="(no date)"
            SUBJECT_LIST+="────────────────────────────────\n"
            SUBJECT_LIST+="  Subject : $SUBJ_HDR\n"
            SUBJECT_LIST+="  From    : $FROM_HDR\n"
            SUBJECT_LIST+="  Date    : $DATE_HDR\n"
            # Mark as seen
            echo "$f" >> "$SEEN_FILE"
        done

        BODY="$(printf '%b' "
========================================
  MISSIRIA MAIL NOTIFIER
========================================
  Account  : $EMAIL
  New mail : $COUNT message(s)
========================================

MESSAGES RECEIVED:

$SUBJECT_LIST
────────────────────────────────

Open webmail: $WEBMAIL

--
MISSIRIA Notification System
")"

        "$SENDMAIL" -f "$NOTIFY_FROM" "$NOTIFY_TO" <<EOF
From: MISSIRIA Notifier <$NOTIFY_FROM>
To: $NOTIFY_TO
Subject: [Mail] $COUNT new — $EMAIL
MIME-Version: 1.0
Content-Type: text/plain; charset=UTF-8

$BODY
EOF

        echo "$(date): Notified $COUNT new mail(s) for $EMAIL"
    fi

    # Prune seen file — keep only filenames still present in new/
    CURRENT_LIST=$(ls "$MAILDIR" 2>/dev/null)
    if [[ -n "$CURRENT_LIST" ]]; then
        grep -F "$CURRENT_LIST" "$SEEN_FILE" > "${SEEN_FILE}.tmp" 2>/dev/null || true
    else
        > "${SEEN_FILE}.tmp"
    fi
    mv "${SEEN_FILE}.tmp" "$SEEN_FILE"

done < "$USERS_FILE"
