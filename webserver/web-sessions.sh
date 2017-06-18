#!/bin/bash
#
# Display current web sessions.
#

ACCESS_LOG="/var/log/apache2/project-ssl-access.log"
SERVER_IP="1.2.3.4"

declare -i SESSION_MAX_LENGTH="600"

Exclude() {
    local IP="$1"
    local UA="$2"
    local REQUEST="$3"

    test "$IP" == "$SERVER_IP" && return 0
    test "$UA" == "Amazon CloudFront" && return 0
    test "$UA" == "Pingdom.com_bot_version_1.4_(http://www.pingdom.com/)" && return 0
    test "$UA" == "HetrixTools.COM Uptime Monitoring Bot. https://hetrixtools.com/uptime-monitoring-bot.html" && return 0

    # Search engines
    [[ "$IP" =~ ^66\.249\.[6789] ]] && [ "$UA" != "${UA/ Googlebot\//}" ] && return 0
    [[ "$IP" =~ ^66\.249\.[6789] ]] && [ "$UA" != "${UA/Googlebot-Image\//}" ] && return 0
    [ "$UA" != "${UA/ Baiduspider\//}" ] && return 0
    [ "$UA" != "${UA/ bingbot\//}" ] && return 0
    [ "$UA" != "${UA/ Yahoo\! Slurp/}" ] && return 0
    [ "$UA" != "${UA/ YandexBot\//}" ] && return 0

    # SEO
    [ "$UA" != "${UA/ AhrefsBot\//}" ] && return 0
    [ "$UA" != "${UA/ DotBot\//}" ] && return 0
    [ "$UA" != "${UA/ MJ12bot\//}" ] && return 0
    [ "$UA" != "${UA/ seoscanners.net\//}" ] && return 0
    [ "$UA" != "${UA/ spbot\//}" ] && return 0

    # Libraries, CLI clients
    #[ "$UA" != "${UA/Wget\/1./}" ] && return 0
    #[ "$UA" != "${UA/curl\/7./}" ] && return 0
    #[ "$UA" != "${UA/Go-http-client\/1./}" ] && return 0
    #[ "$UA" != "${UA/nutch-1.*\/Nutch-1./}" ] && return 0

    # Others
    [ "$UA" != "${UA/AdsBot-Google/}" ] && return 0
    [ "$UA" != "${UA/facebookexternalhit\//}" ] && return 0

    return 1
}

Display_sessions() {
    local ID
    local GEO
    local PTR
    local REQUEST

    for ID in "${SESSIONS[@]}"; do
        GEO="$(geoiplookup -f /var/lib/geoip-database-contrib/GeoLiteCity.dat "${SESSION_DATA[${ID}_IP]}" | cut -d ":" -f 2-)"
        # Trim leading space
        GEO="${GEO# }"
        if [ "${GEO/N\/A,/}" != "$GEO" ]; then
            PTR="$(getent hosts "${SESSION_DATA[${ID}_IP]}")"
            if [ $? -eq 0 ]; then
                GEO="${PTR##* }"
            fi
        fi
        REQUEST="${SESSION_DATA[${ID}_REQUEST]}"
        if [ ${#REQUEST} -gt 53 ]; then
            REQUEST="${REQUEST:0:20}...${REQUEST:(-30)}"
        fi
        echo "${SESSION_DATA[${ID}_MARK]}${SESSION_DATA[${ID}_IP]}${TAB}${GEO:0:30}${TAB}${REQUEST}${TAB}${SESSION_DATA[${ID}_UA]:0:60}"
    done
}

Session_gc() {
    local -i NOW
    local -i EXPIRATION
    local -i INDEX
    local ID

    NOW="$(date "+%s")"
    EXPIRATION="$((NOW - SESSION_MAX_LENGTH))"

    for INDEX in "${!SESSIONS[@]}"; do
        ID="${SESSIONS[$INDEX]}"
        if [ "${SESSION_DATA[${ID}_TIME]}" -lt "$EXPIRATION" ]; then
            # Destroy session
            unset SESSIONS[$INDEX]
            unset SESSION_DATA["${ID}_IP"]
            unset SESSION_DATA["${ID}_UA"]
            unset SESSION_DATA["${ID}_REQUEST"]
            unset SESSION_DATA["${ID}_TIME"]
            unset SESSION_DATA["${ID}_MARK"]
        fi
    done
}

Session_exists() {
    local QUERY="$1"
    local ID

    for ID in "${SESSIONS[@]}"; do
        if [ "$ID" == "$QUERY" ]; then
            return 0
        fi
    done

    return 1
}

Waiting() {
    local I

    # Proper exit
    trap "exit" SIGHUP

    while true; do
        # shellcheck disable=SC2034
        for I in {1..3}; do
            sleep 0.5; echo -n "."
        done
        # Delete line
        sleep 0.5; echo -e -n "\r   \r"
    done
}

Is_static() {
    local REQUEST="$1"
    local URL

    # Remove method
    URL="${REQUEST#* }"
    # Remove protocol
    URL="${URL% *}"
    # Remove query string
    URL="${URL%%\?*}"

    # Exclude possible HTML
    if [ "${URL%.html}" != "$URL" ] \
        || [ "${URL%.htm}" != "$URL" ] \
        || [ "${URL%.aspx}" != "$URL" ] \
        || [ "${URL%.php}" != "$URL" ]; then
        return 1
    fi

    # Having an extension?
    [[ "$URL" =~ \.[a-z]{3,4}$ ]]
}

# shellcheck disable=SC2155
declare -r TAB="$(echo -e -n "\t")"
declare -a SESSIONS
declare -A SESSION_DATA
COLOR_BRIGHT="$(tput bold)"
COLOR_YELLOW="$(tput setaf 3)"
COLOR_RED="$(tput setaf 1)"
COLOR_INVERT="$(tput setaf 0; tput setab 7)"
COLOR_RESET="$(tput sgr0)"

Waiting &
while read -r LOG_LINE; do
    printf -v NOW "%(%s)T" -1

    # Parse access log line
    IP="${LOG_LINE%% *}"
    UA="$(cut -d '"' -f 6 <<< "$LOG_LINE")"
    REQUEST="$(cut -d '"' -f 2 <<< "$LOG_LINE")"

    if Exclude "$IP" "$UA" "$REQUEST"; then
        continue
    fi

    STATUS="$(cut -d '"' -f 3 <<< "$LOG_LINE")"
    STATUS="${STATUS:1:3}"
    APACHE_TIME="$(sed -n -e 's|^.* \[\([0-9]\+\)/\(\S\+\)/\([0-9]\+\):\([0-9]\+\):\([0-9]\+\):\([0-9]\+\) .*$|\1 \2 \3 \4:\5:\6|p' <<< "$LOG_LINE")"
    TIME="$(date --date "$APACHE_TIME" "+%s" 2> /dev/null)"
    # If time parsing fails
    if [ -z "$TIME" ]; then
        TIME="$NOW"
    fi

    # Set session data
    ID="$(md5sum <<< "${IP}|${UA}")"
    ID="${ID%% *}"
    SESSION_DATA["${ID}_TIME"]="$TIME"
    # Default status
    SESSION_DATA["${ID}_MARK"]="_"

    # New session
    if ! Session_exists "$ID"; then
        SESSIONS+=( "$ID" )
        SESSION_DATA["${ID}_IP"]="$IP"
        SESSION_DATA["${ID}_UA"]="$UA"
        SESSION_DATA["${ID}_MARK"]="N"
    fi

    # Set final status
    case "${STATUS:0:1}" in
        3)
            if [ "${SESSION_DATA[${ID}_MARK]}" == N ]; then
                SESSION_DATA["${ID}_MARK"]="8"
            else
                SESSION_DATA["${ID}_MARK"]="3"
            fi
            ;;
        4)
            if [ "${SESSION_DATA[${ID}_MARK]}" == N ]; then
                SESSION_DATA["${ID}_MARK"]="9"
            else
                SESSION_DATA["${ID}_MARK"]="4"
            fi
            ;;
        5)
            if [ "${SESSION_DATA[${ID}_MARK]}" == N ]; then
                SESSION_DATA["${ID}_MARK"]="0"
            else
                SESSION_DATA["${ID}_MARK"]="5"
            fi
            ;;
    esac

    # Keep previous non-static request
    if [ -z "${SESSION_DATA[${ID}_REQUEST]}" ] || Is_static "${SESSION_DATA[${ID}_REQUEST]}"; then
        SESSION_DATA["${ID}_REQUEST"]="$REQUEST"
    fi

    # Prevent continuous refresh
    if [ "$LAST_DISPLAY" == "$NOW" ]; then
        continue
    fi

    LAST_DISPLAY="$NOW"
    jobs -p | xargs -r kill -s SIGHUP
    clear
    Display_sessions \
        | column -s "$TAB" -t -c "$((COLUMNS + 1))" \
        | while read -r SESSION_LINE; do
            case "${SESSION_LINE:0:1}" in
                N)
                    echo "${COLOR_BRIGHT}${SESSION_LINE:1}${COLOR_RESET}"
                    ;;
                3)
                    echo "${COLOR_YELLOW}${SESSION_LINE:1}${COLOR_RESET}"
                    ;;
                4)
                    echo "${COLOR_RED}${SESSION_LINE:1}${COLOR_RESET}"
                    ;;
                5)
                    echo "${COLOR_INVERT}${SESSION_LINE:1}${COLOR_RESET}"
                    ;;
                8)
                    echo "${COLOR_BRIGHT}${COLOR_YELLOW}${SESSION_LINE:1}${COLOR_RESET}"
                    ;;
                9)
                    echo "${COLOR_BRIGHT}${COLOR_RED}${SESSION_LINE:1}${COLOR_RESET}"
                    ;;
                0)
                    echo "${COLOR_BRIGHT}${COLOR_INVERT}${SESSION_LINE:1}${COLOR_RESET}"
                    ;;
                *)
                    echo "${SESSION_LINE:1}"
                    ;;
            esac
        done
    Waiting &

    # Revert bright colors for new sessions
    for ID in "${SESSIONS[@]}"; do
        case "${SESSION_DATA[${ID}_MARK]}" in
            N)
                SESSION_DATA["${ID}_MARK"]="_"
                ;;
            8)
                SESSION_DATA["${ID}_MARK"]="3"
                ;;
            9)
                SESSION_DATA["${ID}_MARK"]="4"
                ;;
            0)
                SESSION_DATA["${ID}_MARK"]="5"
                ;;
        esac
    done

    # Run gc in 1:10 chance
    if [ "$RANDOM" -lt 3276 ]; then
        Session_gc
    fi
done < <(tail -q -n 0 -f "$ACCESS_LOG")
