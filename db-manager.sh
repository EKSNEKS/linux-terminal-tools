#!/bin/bash

# Configuration
DB_USER="root"

# 1. Main Menu
echo "--- Master Database & Server Utility ---"
mysql -u "$DB_USER" -e "SHOW DATABASES;"
echo "----------------------------------------"

echo "Select an action:"
echo "1) CLEANUP Tables inside a database (Prefix or Plugins)"
echo "2) DROP an entire database"
echo "3) SEARCH & REPLACE text across ALL tables (Global)"
echo "4) WORDPRESS DOMAIN MIGRATOR (siteurl, home, guid, content)"
echo "5) RENAME Physical Files in a Directory (e.g., Media Uploads)"
echo "6) EXPORT a Database (Quick Select by Number)"
echo "7) EXIT"
read -p "Choice [1-7]: " MAIN_CHOICE

# =======================================================
# OPTION 1: CLEANUP TABLES
# =======================================================
if [ "$MAIN_CHOICE" == "1" ]; then
    read -p "Enter the Database Name: " DB_NAME
    echo -e "\n--- Current Tables in $DB_NAME ---"
    mysql -u "$DB_USER" -D "$DB_NAME" -e "SHOW TABLES;"
    echo "----------------------------------"

    echo "Select cleanup mode:"
    echo "1) DELETE EVERYTHING with a specific prefix"
    echo "2) DELETE ONLY 'Useless' Plugin Tables"
    read -p "Choice [1 or 2]: " MODE

    if [ "$MODE" == "1" ]; then
        read -p "Enter the prefix to wipe out (e.g., iPe_): " TARGET_PREFIX
        TABLES=$(mysql -u "$DB_USER" -N -e "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$DB_NAME' AND TABLE_NAME LIKE '${TARGET_PREFIX}%';")
    elif [ "$MODE" == "2" ]; then
        read -p "Enter the prefix these plugins use (e.g., iPe_): " P_PREFIX
        USELESS_LIST=("${P_PREFIX}wpforms_logs" "${P_PREFIX}wpforms_payment_meta" "${P_PREFIX}wpforms_payments" "${P_PREFIX}wpforms_tasks_meta" "${P_PREFIX}wpmailsmtp_debug_events" "${P_PREFIX}wpmailsmtp_tasks_meta" "${P_PREFIX}rank_math_internal_links" "${P_PREFIX}rank_math_internal_meta")
        TABLES=""
        for T in "${USELESS_LIST[@]}"; do
            FOUND=$(mysql -u "$DB_USER" -N -e "SELECT TABLE_NAME FROM information_schema.TABLES WHERE TABLE_SCHEMA = '$DB_NAME' AND TABLE_NAME = '$T';")
            if [ ! -z "$FOUND" ]; then TABLES="$TABLES $FOUND"; fi
        done
    fi

    if [ -z "$TABLES" ]; then echo "No matching tables found."; exit 0; fi

    echo -e "\n--- TARGETED FOR DELETION ---"
    for T in $TABLES; do echo " - $T"; done
    read -p "Proceed? (y/n): " CONFIRM

    if [ "$CONFIRM" == "y" ]; then
        mysqldump -u "$DB_USER" "$DB_NAME" > "/tmp/cleanup_backup.sql"
        for TABLE in $TABLES; do
            mysql -u "$DB_USER" -D "$DB_NAME" -e "SET FOREIGN_KEY_CHECKS = 0; DROP TABLE \`$TABLE\`; SET FOREIGN_KEY_CHECKS = 1;"
            echo "Deleted: $TABLE"
        done
        echo "Cleanup complete."
    fi

# =======================================================
# OPTION 2: DROP ENTIRE DB
# =======================================================
elif [ "$MAIN_CHOICE" == "2" ]; then
    read -p "Enter the name of the DATABASE to DELETE: " DROP_DB
    EXISTS=$(mysql -u "$DB_USER" -e "SHOW DATABASES LIKE '$DROP_DB';")
    if [ -z "$EXISTS" ]; then echo "Error: Database '$DROP_DB' not found."; exit 1; fi

    echo -e "\n!!! WARNING: YOU ARE ABOUT TO DELETE THE ENTIRE DATABASE: $DROP_DB !!!"
    read -p "Type the database name again to confirm deletion: " CONFIRM_NAME
    if [ "$CONFIRM_NAME" == "$DROP_DB" ]; then
        mysql -u "$DB_USER" -e "DROP DATABASE \`$DROP_DB\`;"
        echo "Database $DROP_DB has been deleted."
    else
        echo "Confirmation failed. Aborting."
    fi

# =======================================================
# OPTION 3: SEARCH & REPLACE (Global Text)
# =======================================================
elif [ "$MAIN_CHOICE" == "3" ]; then
    read -p "Enter the Database Name: " DB_NAME
    EXISTS=$(mysql -u "$DB_USER" -e "SHOW DATABASES LIKE '$DB_NAME';")
    if [ -z "$EXISTS" ]; then echo "Error: Database '$DB_NAME' not found."; exit 1; fi

    echo -e "\n--- Search & Replace Configuration ---"
    read -p "Enter the string to find: " SEARCH_STR
    read -p "Enter the NEW string: " REPLACE_STR
    if [ -z "$SEARCH_STR" ]; then echo "Error: Search string cannot be empty."; exit 1; fi

    read -p "Ready to execute globally? (y/n): " CONFIRM
    if [ "$CONFIRM" == "y" ]; then
        COLUMNS=$(mysql -u "$DB_USER" -N -e "SELECT TABLE_NAME, COLUMN_NAME FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = '$DB_NAME' AND DATA_TYPE IN ('varchar', 'text', 'mediumtext', 'longtext');")
        TOTAL_FOUND=0
        while read -r TABLE COLUMN; do
            OUTPUT=$(mysql -u "$DB_USER" -D "$DB_NAME" -vvv -e "UPDATE \`$TABLE\` SET \`$COLUMN\` = REPLACE(\`$COLUMN\`, '$SEARCH_STR', '$REPLACE_STR') WHERE \`$COLUMN\` LIKE '%$SEARCH_STR%'; " 2>&1)
            COUNT=$(echo "$OUTPUT" | grep -o "Changed: [0-9]*" | awk '{print $2}')
            if [[ ! -z "$COUNT" && "$COUNT" -gt 0 ]]; then
                echo " -> $TABLE.$COLUMN : Replaced $COUNT times"
                TOTAL_FOUND=$((TOTAL_FOUND + COUNT))
            fi
        done <<< "$COLUMNS"
        echo "Total occurrences replaced: $TOTAL_FOUND"
    fi

# =======================================================
# OPTION 4: WORDPRESS DOMAIN MIGRATOR
# =======================================================
elif [ "$MAIN_CHOICE" == "4" ]; then
    read -p "Enter the Database Name: " DB_NAME
    EXISTS=$(mysql -u "$DB_USER" -e "SHOW DATABASES LIKE '$DB_NAME';")
    if [ -z "$EXISTS" ]; then echo "Error: Database '$DB_NAME' not found."; exit 1; fi

    echo -e "\n--- Table Preview for '$DB_NAME' ---"
    mysql -u "$DB_USER" -D "$DB_NAME" -e "SHOW TABLES;" | head -n 15
    echo "--------------------------------------"

    read -p "Enter the WordPress table prefix (e.g., wp_, iPe_): " WP_PREFIX
    read -p "Enter the OLD domain (e.g., https://old.com): " OLD_DOMAIN
    read -p "Enter the NEW domain (e.g., https://new.com): " NEW_DOMAIN

    if [ -z "$OLD_DOMAIN" ] || [ -z "$NEW_DOMAIN" ]; then echo "Error: Domains cannot be empty."; exit 1; fi

    read -p "Proceed with domain swap? (y/n): " CONFIRM
    if [ "$CONFIRM" == "y" ]; then
        mysql -u "$DB_USER" -D "$DB_NAME" -e "UPDATE \`${WP_PREFIX}options\` SET option_value = REPLACE(option_value, '$OLD_DOMAIN', '$NEW_DOMAIN') WHERE option_name = 'home' OR option_name = 'siteurl';"
        mysql -u "$DB_USER" -D "$DB_NAME" -e "UPDATE \`${WP_PREFIX}posts\` SET guid = REPLACE(guid, '$OLD_DOMAIN', '$NEW_DOMAIN');"
        mysql -u "$DB_USER" -D "$DB_NAME" -e "UPDATE \`${WP_PREFIX}posts\` SET post_content = REPLACE(post_content, '$OLD_DOMAIN', '$NEW_DOMAIN');"
        mysql -u "$DB_USER" -D "$DB_NAME" -e "UPDATE \`${WP_PREFIX}postmeta\` SET meta_value = REPLACE(meta_value, '$OLD_DOMAIN', '$NEW_DOMAIN') WHERE meta_value NOT LIKE 'a:%' AND meta_value NOT LIKE 'O:%';"
        echo "WordPress Migration Complete."
    fi

# =======================================================
# OPTION 5: MASS FILE RENAMER
# =======================================================
elif [ "$MAIN_CHOICE" == "5" ]; then
    echo -e "\n--- Physical File Renamer ---"
    read -p "Enter the FULL PATH to the directory (e.g., /var/www/IT/ispe/wp-content/uploads): " TARGET_DIR

    if [ ! -d "$TARGET_DIR" ]; then
        echo "Error: Directory '$TARGET_DIR' does not exist."
        exit 1
    fi

    read -p "Enter the OLD string in the filename (e.g., iptvsmarterspro-europe.com): " OLD_STR
    read -p "Enter the NEW string to replace it with: " NEW_STR

    if [ -z "$OLD_STR" ]; then echo "Error: Old string cannot be empty."; exit 1; fi

    echo -e "\nScanning '$TARGET_DIR' recursively for files containing '$OLD_STR'..."

    MATCHES=$(find "$TARGET_DIR" -depth -name "*${OLD_STR}*")

    if [ -z "$MATCHES" ]; then
        echo "No files found matching that string."
        exit 0
    fi

    COUNT=$(echo "$MATCHES" | wc -l)
    echo "Found $COUNT files/directories to rename."
    read -p "Proceed with renaming? (y/n): " CONFIRM

    if [ "$CONFIRM" == "y" ]; then
        echo "$MATCHES" | while read -r FILE; do
            DIR=$(dirname "$FILE")
            BASE=$(basename "$FILE")
            NEW_BASE="${BASE//$OLD_STR/$NEW_STR}"
            mv "$FILE" "$DIR/$NEW_BASE"
            echo "Renamed -> $NEW_BASE"
        done
        echo "Successfully renamed files."
    else
        echo "Aborted."
    fi

# =======================================================
# OPTION 6: EXPORT DATABASE (mysqldump Quick Selection)
# =======================================================
elif [ "$MAIN_CHOICE" == "6" ]; then
    echo -e "\n--- Export Database (Select Number) ---"
    
    # Filter out system databases for a cleaner list
    mapfile -t DB_LIST < <(mysql -u "$DB_USER" -N -e "SHOW DATABASES;" | grep -vE "(information_schema|performance_schema|mysql|sys)")

    for i in "${!DB_LIST[@]}"; do
        printf "[%2d] %s\n" "$((i+1))" "${DB_LIST[$i]}"
    done

    read -p "Enter the number of the DB to export: " DB_NUM
    
    INDEX=$((DB_NUM-1))
    if [[ "$INDEX" -ge 0 && "$INDEX" -lt "${#DB_LIST[@]}" ]]; then
        SELECTED_DB="${DB_LIST[$INDEX]}"
        
        # Fixed path as requested
        EXPORT_FILE="/home/missiria/dump.sql"
        
        echo "🚀 Running: mysqldump -u root $SELECTED_DB > $EXPORT_FILE"
        mysqldump -u root "$SELECTED_DB" > "$EXPORT_FILE"
        
        if [ $? -eq 0 ]; then
            echo "✅ SUCCESS: Database '$SELECTED_DB' exported to $EXPORT_FILE"
        else
            echo "❌ ERROR: Export failed."
        fi
    else
        echo "Invalid selection."
    fi

# =======================================================
# OPTION 7: EXIT
# =======================================================
else
    echo "Exiting."
    exit 0
fi
