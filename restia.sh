#!/bin/bash

export HOME=/root

# consts
readonly TIMER="$(date +%s)"
readonly SCRIPT_START_DATE="$(date +%Y-%m-%d-%H-%M-%S)"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_BASE_NAME="${SCRIPT_NAME/.sh/}"
readonly SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"

readonly COMMANDS=(help repo snap status backup restore enable disable)
readonly REPO_COMMANDS=(init)
readonly SNAP_COMMANDS=(list create restore delete)

readonly BASE_DIRECTORY_PATH="/root/restia"
readonly CONFIG_DIRECTORY_PATH="${BASE_DIRECTORY_PATH}/config"
readonly MOUNT_DIRECTORY_PATH="/mnt/${SCRIPT_BASE_NAME}"
readonly SCRIPT_DIRECTORY_PATH="${BASE_DIRECTORY_PATH}/script"
readonly SERVICE_DIRECTORY_PATH="${BASE_DIRECTORY_PATH}/service"
readonly LOG_DIRECTORY_PATH="${BASE_DIRECTORY_PATH}/log"
readonly GENERAL_LOG_DIRECTORY_PATH="${LOG_DIRECTORY_PATH}/general"
readonly BACKUP_LOG_DIRECTORY_PATH="${LOG_DIRECTORY_PATH}/backup"
readonly RESTORE_LOG_DIRECTORY_PATH="${LOG_DIRECTORY_PATH}/restore"

readonly LOG_FILE_NAME="${SCRIPT_BASE_NAME}-${SCRIPT_START_DATE}.log"
readonly BACKUP_LOG_FILE_NAME="$(echo "${LOG_FILE_NAME}" | tr -d '.log')-backup.log"

readonly RCLONE_WEBDAV_SERIVCE_NAME="${SCRIPT_BASE_NAME}-webdav-server"
readonly HOT_BACKUP_SCRIPT_SERVICE_NAME="${SCRIPT_BASE_NAME}-hot-backup"
readonly COLD_BACKUP_SCRIPT_SERVICE_NAME="${SCRIPT_BASE_NAME}-cold-backup"
readonly HOT_BACKUP_SCRIPT_SERVICE_TIMER_NAME="${SCRIPT_BASE_NAME}-hot-backup"
readonly COLD_BACKUP_SCRIPT_SERVICE_TIMER_NAME="${SCRIPT_BASE_NAME}-cold-backup"

readonly LOG_FILE_PATH="${GENERAL_LOG_DIRECTORY_PATH}/${LOG_FILE_NAME}"
readonly RESULT_FILE_PATH="${GENERAL_LOG_DIRECTORY_PATH}/${SCRIPT_BASE_NAME}-${SCRIPT_START_DATE}.result"
readonly CONFIG_FILE_PATH="${CONFIG_DIRECTORY_PATH}/${SCRIPT_BASE_NAME}.conf"
readonly ONLINE_CLIENTS_FILE_URL="https://raw.githubusercontent.com/zbalint/restia/master/config/clients.conf"
readonly CLIENTS_FILE_PATH="${CONFIG_DIRECTORY_PATH}/clients.conf"
readonly RCLONE_WEBDAV_SCRIPT_PATH="${SCRIPT_DIRECTORY_PATH}/${SCRIPT_BASE_NAME}-webdav-server.sh"
readonly RCLONE_WEBDAV_SERIVCE_PATH="${SERVICE_DIRECTORY_PATH}/${RCLONE_WEBDAV_SERIVCE_NAME}.service"
readonly HOT_BACKUP_SCRIPT_SERVICE_PATH="${SERVICE_DIRECTORY_PATH}/${HOT_BACKUP_SCRIPT_SERVICE_NAME}.service"
readonly COLD_BACKUP_SCRIPT_SERVICE_PATH="${SERVICE_DIRECTORY_PATH}/${COLD_BACKUP_SCRIPT_SERVICE_NAME}.service"
readonly HOT_BACKUP_SCRIPT_SERVICE_TIMER_PATH="${SERVICE_DIRECTORY_PATH}/${HOT_BACKUP_SCRIPT_SERVICE_TIMER_NAME}.timer"
readonly COLD_BACKUP_SCRIPT_SERVICE_TIMER_PATH="${SERVICE_DIRECTORY_PATH}/${COLD_BACKUP_SCRIPT_SERVICE_TIMER_NAME}.timer"

readonly SSHFS_OPTIONS="reconnect,cache=no,compression=no,Ciphers=chacha20-poly1305@openssh.com"
DEBUG_LOG="false"


IFS='' read -r -d '' RCLONE_WEBDAV_SCRIPT <<"EOF"
#!/bin/bash
rclone serve webdav BACKUP_LOG_DIRECTORY_PATH --addr WEBDAV_LISTEN_ADDRESS
EOF

IFS='' read -r -d '' RCLONE_WEBDAV_SERVICE <<"EOF"
[Unit]
Description=Restia Rclone WebDAV Service
After=network.target

[Service]
ExecStart=bash RCLONE_WEBDAV_SCRIPT_PATH
Restart=always

[Install]
WantedBy=default.target

EOF

IFS='' read -r -d '' HOT_BACKUP_SCRIPT_SERVICE <<"EOF"
[Unit]
Description=restia - homelab backup service for hot backups
After=network.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=bash SCRIPT_PATH backup hot
EOF

IFS='' read -r -d '' COLD_BACKUP_SCRIPT_SERVICE <<"EOF"
[Unit]
Description=restia - homelab backup service for cold backups
After=network.target
Wants=network.target

[Service]
Type=oneshot
ExecStart=bash SCRIPT_PATH backup cold
EOF

IFS='' read -r -d '' HOT_BACKUP_SCRIPT_SERVICE_TIMER <<"EOF"
[Unit]
Description=restia - homelab backup service timer for hot backups
[Timer]
OnCalendar=HOT_BACKUP_FREQUENCY
Persistent=true
[Install]
WantedBy=timers.target
EOF

IFS='' read -r -d '' COLD_BACKUP_SCRIPT_SERVICE_TIMER <<"EOF"
[Unit]
Description=restia - homelab backup service timer for cold backups
[Timer]
OnCalendar=COLD_BACKUP_FREQUENCY
Persistent=true
[Install]
WantedBy=timers.target
EOF


function enable() {
    local HOT_BACKUP_FREQUENCY
    local COLD_BACKUP_FREQUENCY
    local WEBDAV_LISTEN_ADDRESS

    HOT_BACKUP_FREQUENCY=$(get_config_value "HOT_BACKUP_FREQUENCY")
    COLD_BACKUP_FREQUENCY=$(get_config_value "COLD_BACKUP_FREQUENCY")
    WEBDAV_LISTEN_ADDRESS=$(get_config_value "WEBDAV_LISTEN_ADDRESS")

    log_info "Temporary remove clients file list."
    mv "${CLIENTS_FILE_PATH}" "${CLIENTS_FILE_PATH}.orig" && touch "${CLIENTS_FILE_PATH}" && chmod 0600 "${CLIENTS_FILE_PATH}"

    log_info "Creating webdav service."
    
    RCLONE_WEBDAV_SCRIPT_TEST="${RCLONE_WEBDAV_SCRIPT/BACKUP_LOG_DIRECTORY_PATH/${BACKUP_LOG_DIRECTORY_PATH}}"
    RCLONE_WEBDAV_SCRIPT_TEST="${RCLONE_WEBDAV_SCRIPT_TEST/WEBDAV_LISTEN_ADDRESS/${WEBDAV_LISTEN_ADDRESS}}"
    echo "${RCLONE_WEBDAV_SCRIPT_TEST}" > "${RCLONE_WEBDAV_SCRIPT_PATH}"
    
    echo "${RCLONE_WEBDAV_SERVICE/RCLONE_WEBDAV_SCRIPT_PATH/${RCLONE_WEBDAV_SCRIPT_PATH}}" > "${RCLONE_WEBDAV_SERIVCE_PATH}"

    cp "${RCLONE_WEBDAV_SERIVCE_PATH}" /etc/systemd/system/

    log_info "Creating hot backup service."
    echo "${HOT_BACKUP_SCRIPT_SERVICE/SCRIPT_PATH/${SCRIPT_PATH}}" > "${HOT_BACKUP_SCRIPT_SERVICE_PATH}"
    cp "${HOT_BACKUP_SCRIPT_SERVICE_PATH}" /etc/systemd/system/

    log_info "Creating cold backup service."
    echo "${COLD_BACKUP_SCRIPT_SERVICE/SCRIPT_PATH/${SCRIPT_PATH}}" > "${COLD_BACKUP_SCRIPT_SERVICE_PATH}"
    cp "${COLD_BACKUP_SCRIPT_SERVICE_PATH}" /etc/systemd/system/

    log_info "Creating hot backup timer."
    echo "${HOT_BACKUP_SCRIPT_SERVICE_TIMER/HOT_BACKUP_FREQUENCY/${HOT_BACKUP_FREQUENCY}}" > "${HOT_BACKUP_SCRIPT_SERVICE_TIMER_PATH}"
    cp "${HOT_BACKUP_SCRIPT_SERVICE_TIMER_PATH}" /etc/systemd/system/

    log_info "Creating cold backup timer."
    echo "${COLD_BACKUP_SCRIPT_SERVICE_TIMER/COLD_BACKUP_FREQUENCY/${COLD_BACKUP_FREQUENCY}}" > "${COLD_BACKUP_SCRIPT_SERVICE_TIMER_PATH}"
    cp "${COLD_BACKUP_SCRIPT_SERVICE_TIMER_PATH}" /etc/systemd/system/

    systemctl daemon-reload

    systemctl enable --now "${RCLONE_WEBDAV_SERIVCE_NAME}"
    systemctl enable --now "${HOT_BACKUP_SCRIPT_SERVICE_TIMER_NAME}.timer"
    systemctl enable --now "${COLD_BACKUP_SCRIPT_SERVICE_TIMER_NAME}.timer"
    
    systemctl status "${RCLONE_WEBDAV_SERIVCE_NAME}" --no-pager
    systemctl status "${HOT_BACKUP_SCRIPT_SERVICE_TIMER_NAME}" --no-pager
    systemctl status "${COLD_BACKUP_SCRIPT_SERVICE_TIMER_NAME}" --no-pager
    
    log_info "You can watch the logs with the following commands:"
    log_info "journalctl --unit ${RCLONE_WEBDAV_SERIVCE_NAME}"
    log_info "journalctl --unit ${HOT_BACKUP_SCRIPT_SERVICE_TIMER_NAME}"
    log_info "journalctl --unit ${COLD_BACKUP_SCRIPT_SERVICE_TIMER_NAME}"

    log_info "Restore original clients file list."
    mv "${CLIENTS_FILE_PATH}.orig" "${CLIENTS_FILE_PATH}"
}

function disable() {
    systemctl disable --now "${RCLONE_WEBDAV_SERIVCE_NAME}"
    systemctl disable --now "${HOT_BACKUP_SCRIPT_SERVICE_TIMER_NAME}"
    systemctl disable --now "${COLD_BACKUP_SCRIPT_SERVICE_TIMER_NAME}"

    rm -f "/etc/systemd/system/${RCLONE_WEBDAV_SERIVCE_NAME}.service"
    rm -f "/etc/systemd/system/${HOT_BACKUP_SCRIPT_SERVICE_NAME}.service"
    rm -f "/etc/systemd/system/${COLD_BACKUP_SCRIPT_SERVICE_NAME}.service"
    rm -f "/etc/systemd/system/${HOT_BACKUP_SCRIPT_SERVICE_TIMER_NAME}.timer"
    rm -f "/etc/systemd/system/${COLD_BACKUP_SCRIPT_SERVICE_TIMER_NAME}.timer"
    
    systemctl daemon-reload
}

# Check if the passed variable is empty or undefined.
function is_var_empty() {
    local var="$1"

    if [ -z "${var:-}" ]; then
        return 0
    else
        return 1
    fi
}

# Check if the variable is not empty or undefined.
function is_var_not_empty() {
    local var="$1"

    if [ -z "${var}" ]; then
        return 1
    else
        return 0
    fi
}

# Check if the passed variable is NULL.
function is_var_null() {
    local var="$1"

    if [ "${var}" == "NULL" ]; then
        return 0
    else
        return 1
    fi
}

# Check if the passed variable is euqals of the value of str.
function is_var_equals() {
    local var="$1"
    local str="$2"

    if [ "${var}" == "${str}" ]; then
        return 0
    else
        return 1
    fi
}

# Check if the program received in the first argument is installed on the system
function is_installed() {
    local command="$1"

    if command -v "${command}" >/dev/null; then
        return 0
    fi

    return 1
}

# Check if restic is installed
function is_restic_installed() {
    if is_installed "restic"; then
        return 0
    fi

    return 1
}

# Check if kopia is installed
function is_kopia_installed() {
    if is_installed "kopia"; then
        return 0
    fi

    return 1
}

# Check if sshfs is installed
function is_sshfs_installed() {
    if is_installed "sshfs"; then
        return 0
    fi

    return 1
}

# Get elapsed time since the start of the script
function get_run_time() {
    local start
    local stop
    local elapsed

    start="${TIMER}"
    stop="$(date +%s)"
    elapsed=$(("${stop}"-"${start}"))

    date -u -d @${elapsed} +%H:%M:%S
}

# Log message to stdout
function log() {
    local level="$1"; shift
    local message_raw="$*"
    local message
    local funcname
    local date_string
    local time_elapsed

    message="$(echo "${message_raw}" | tr -d '\r')"
    
    funcname=$(echo "${FUNCNAME[*]}" | tr ' ' '\n' | tac | grep -v log | tr '\n' '\\');
    # date_string=$(date +%Y-%m-%d" "%H:%M:%S.%N)
    date_string=$(date +%H:%M:%S.%N)
    time_elapsed="$(get_run_time)"

    if is_var_equals "${DEBUG_LOG}" "false"; then
        echo -n "${SCRIPT_BASE_NAME} - [${date_string:0:-6}] [${time_elapsed}] [${level}]: ${message}"
        echo "${SCRIPT_BASE_NAME} - [${date_string:0:-6}] [${time_elapsed}] [${level}]: ${message}" >> "${LOG_FILE_PATH}"
        
        if ! is_var_equals "${level}" "INPUT"; then
            printf "\n"
        fi

        return 0
    fi

    if is_var_empty "${funcname}"; then
        message="The funcname must not be empty or undefined!"
        echo "${SCRIPT_BASE_NAME} - [${date_string:0:-6}] [${FUNCNAME[0]}] [ERROR]: ${message}"
        exit 1
    fi

    if is_var_empty "${level}"; then
        message="The level must not be empty or undefined!"
        echo "${SCRIPT_BASE_NAME} - [${date_string:0:-6}] [${FUNCNAME[0]}] [ERROR]: ${message}"
        exit 1
    fi

    if is_var_empty "${message}"; then
        message="The message must not be empty or undefined!"
        echo "${SCRIPT_BASE_NAME} - [${date_string:0:-6}] [${FUNCNAME[0]}] [ERROR]: ${message}"
        exit 1
    fi

    # prints the log message int the following format SCRIPT_BASE_NAME - [hour:minute:second.nanosecond] [stack trace] [log level]: log message
    echo -n "${SCRIPT_BASE_NAME} - [${date_string:0:-6}] [${time_elapsed}] [${funcname:5:-1}] [${level}]: ${message}"
    echo "${SCRIPT_BASE_NAME} - [${date_string:0:-6}] [${time_elapsed}] [${funcname:5:-1}] [${level}]: ${message}" >> "${LOG_FILE_PATH}"
    # printf "%s" "${SCRIPT_BASE_NAME} - [${date_string:0:-6}] [${funcname:5:-1}] [${level}]: ${message}"
    if ! is_var_equals "${level}" "INPUT"; then
        printf "\n"
    fi
}

# Log formatted error message to the stdout
function log_with_level() {
    local level="$1"; shift
    local message="$*"

    if is_var_empty "${message}"; then
        log "ERROR" "The message must not be empty or undefined!"
        exit 1
    fi

    log "${level}" "${message}"
}

# Log formatted error message to the stdout
function log_error() {
    local message="$*"
    log_with_level "ERROR" "${message}"
}

# Log formatted warning message to the stdout
function log_warn() {
    local message="$*"
    log_with_level "WARN " "${message}"
}

# Log formatted info message to the stdout
function log_info() {
    local message="$*"
    log_with_level "INFO " "${message}"
}

# Log formatted info message to the stdout
function log_input() {
    local message="$*"
    log_with_level "INPUT" "${message}"
}

# Capture output of funcitons and commands
function log_harvest() {
    while IFS= read -r line; do
        if ! is_var_empty "${line}"; then
            log_info "${line}"
        fi 
    done
}

function log_result_header() {
    local result_file="${RESULT_FILE_PATH}"
    local web_viewer_address
    
    web_viewer_address=$(get_config_value "LOG_VIEWER_ADDRESS")
    backup_log_address="${web_viewer_address}/${BACKUP_LOG_FILE_NAME}"
    
    {
        echo "***************************************************************************************"
        echo "********************************** BACKUP RESULT **************************************"
        echo "***************************************************************************************"
        echo "The complete log is available at:"
        echo "${backup_log_address}"
        echo "***************************************************************************************"
    } > "${result_file}"
}

# Log backup result
function log_result() {
    local message="$*"
    local result_file="${RESULT_FILE_PATH}"

    echo -n "${message}" >> "${result_file}"
}

function log_result_end() {
    local result_file="${RESULT_FILE_PATH}"

    printf "\n" >> "${result_file}"
}

function log_result_footer() {
    local result_file="${RESULT_FILE_PATH}"
    echo "***************************************************************************************" >> "${result_file}"
}

function is_host_up() {
    local ping_host="$1"
    local ping_count=5
    local ping_timeout=3

    ping -c ${ping_count} -W ${ping_timeout} "${ping_host}" > /dev/null 2>&1
}

# Check if the file is exists
function is_file_exists() {
    local file="$1"
    
    if [ -e "${file}" ] && [ -r "${file}" ]; then
        return 0
    fi

    return 1
}

# Check if the directory exists
function is_directory_exists() {
    local directory="$1"

    if [ -d "${directory}" ]; then
        return 0
    fi

    return 1
}

# Check if the directory mounted
function is_directory_mounted() {
    local directory="$1"

    if mountpoint -q "${directory}"; then
        return 0
    fi

    return 1
}

function create_directory() {
    local path="$1"

    if mkdir -p "${path}" && chmod 0700 "${path}"; then
        return 0
    fi

    return 1
}

# Check if the file 'file' has the 'permission' permission
function validate_file_permission() {
    local file="$1"
    local permission="$2"

    if [[ $(stat -c "%a" "${file}") -eq "${permission}" ]]; then
        return 0
    fi

    return 1
}

# Check if the file 'file' exists and has a permission 0700
function validate_file() {
    local file="$1"

    if is_file_exists "${file}" && validate_file_permission "${file}" "600"; then
        return 0
    fi

    return 1
}

# Check if the directory 'directory' exists and has a permission 0700
function validate_directory() {
    local directory="$1"

    if is_directory_exists "${directory}" && validate_file_permission "${directory}" "700"; then
        return 0
    fi

    return 1
}

# Send notification to the Gotify server
function send_gotify_notification() {
    local title="$1"; shift
    local message="$*"
    local priority=5
    local gotify_server_url
    local gotify_server_token

    gotify_server_url="$(get_config_value "GOTIFY_SERVER_URL")"
    gotify_server_token="$(get_config_value "GOTIFY_SERVER_TOKEN")"

    if is_var_empty "${message}"; then
        log_error "The message must not be empty or undefined!"
        exit 1
    fi

    if ! curl --insecure -m 10 --retry 2 "${gotify_server_url}/message?token=${gotify_server_token}" -F "title=${title}" -F "message=${message}" -F "priority=${priority}" > /dev/null 2>&1; then
        log_error "Failed to send notification to the Gotify server!"
    fi
}

# Call HealthChecks.io to save backup status
function ping_healthchecks_io() {
    local operation="$1"
    local healthcheck_io
    local result
    healthcheck_io="$(get_config_value "HEALTHCHECKS_IO_ID")"

    case "${operation}" in
        start)
            curl --insecure https://hc-ping.com/"${healthcheck_io}"/start > /dev/null 2>&1
            ;;
        stop)
            result="$(cat "${RESULT_FILE_PATH}")"
            # local status_payload
            # status_payload=$(status 2>&1)
            curl --insecure -fsS --data-raw "${result}" https://hc-ping.com/"${healthcheck_io}" > /dev/null 2>&1
            ;;
        error)
            result="$(cat "${RESULT_FILE_PATH}")"
            # local status_payload
            # status_payload=$(status 2>&1)
            curl --insecure -fsS --data-raw "${result}" https://hc-ping.com/"${healthcheck_io}/fail" > /dev/null 2>&1
            ;;
    esac
}

# Read the config file specified by "CONFIG_FILE_PATH" const
# and if it contains the key specified by local var "key"
# write its content to stdout
function get_config_value() {
    local key="$1"
    local value

    if is_var_empty "${key}"; then
        log_error "ERROR" "The key must not be empty or undefined!"
        exit 1
    fi

    value=$(grep "${key}" "${CONFIG_FILE_PATH}" | cut --only-delimited --delimiter "=" --fields 2 | tr -d "\"" | tr -d "\n" | tr -d "\r")

    if is_var_not_empty "${value}"; then
        echo "${value}"
    else
        echo "NULL"
    fi
}

# Check if config_key is exists in config file and has a value
function validate_config_value() {
    local config_key="$1"
    local config_value

    config_value=$(get_config_value "${config_key}")
    if is_var_null "${config_value}"; then
        log_error "The ${config_key} must not be NULL!"
        exit 1
    fi
}

# Check if config_key is exists in config file and has a value
function validate_optional_config_value() {
    local config_key="$1"
    local config_value

    config_value=$(get_config_value "${config_key}")
    if is_var_null "${config_value}"; then
        return 1
    fi

    return 0
}

# Validate const values and reads and validates config values
function validate_config() {
    # Validate consts

    if ! validate_directory "${BASE_DIRECTORY_PATH}"; then
        log_error "The BASE_DIRECTORY_PATH is empty or the directory does not exists or the directory permissions are wrong!"
        # commented out because the dev environment filesystem permission limitations
        exit 1
    fi
    
    if ! validate_directory "${CONFIG_DIRECTORY_PATH}"; then
        log_error "The CONFIG_DIRECTORY_PATH is empty or the directory does not exists or the directory permissions are wrong!"
        # commented out because the dev environment filesystem permission limitations
        exit 1
    fi
    
    if ! validate_file "${CONFIG_FILE_PATH}"; then
        log_error "The CONFIG_FILE_PATH is empty or the file does not exists or the file permissions are wrong!"
        # commented out because the dev environment filesystem permission limitations
        exit 1
    fi

    if ! validate_file "${CLIENTS_FILE_PATH}"; then
        log_error "The CLIENTS_FILE_PATH is empty or the file does not exists or the file permissions are wrong!"
        # commented out because the dev environment filesystem permission limitations
        exit 1
    else 
        if [ "$(cat "${CLIENTS_FILE_PATH}" | wc -l)" -eq 0 ]; then
            log_warn "The CLIENT_FILE '${CLIENTS_FILE_PATH}' is empty!"
        fi
    fi

    if ! validate_directory "${MOUNT_DIRECTORY_PATH}"; then
        log_error "The MOUNT_DIRECTORY_PATH is empty or the directory does not exists or the directory permissions are wrong!"
        # commented out because the dev environment filesystem permission limitations
        exit 1
    fi

    if ! validate_directory "${LOG_DIRECTORY_PATH}"; then
        log_error "The LOG_DIRECTORY_PATH is empty or the directory does not exists or the directory permissions are wrong!"
        log_info "Creating log directory at ${LOG_DIRECTORY_PATH}."
        if ! create_directory "${LOG_DIRECTORY_PATH}"; then
            log_error "Failed to create log directory!"
            exit 1
        fi
    fi

    if ! validate_directory "${GENERAL_LOG_DIRECTORY_PATH}"; then
        log_error "The GENERAL_LOG_DIRECTORY_PATH is empty or the directory does not exists or the directory permissions are wrong!"
        log_info "Creating log directory at ${GENERAL_LOG_DIRECTORY_PATH}."
        if ! create_directory "${GENERAL_LOG_DIRECTORY_PATH}"; then
            log_error "Failed to create log directory!"
            exit 1
        fi
    fi

    if ! validate_directory "${BACKUP_LOG_DIRECTORY_PATH}"; then
        log_error "The BACKUP_LOG_DIRECTORY_PATH is empty or the directory does not exists or the directory permissions are wrong!"
        log_info "Creating log directory at ${BACKUP_LOG_DIRECTORY_PATH}."
        if ! create_directory "${BACKUP_LOG_DIRECTORY_PATH}"; then
            log_error "Failed to create log directory!"
            exit 1
        fi
    fi

    if ! validate_directory "${RESTORE_LOG_DIRECTORY_PATH}"; then
        log_error "The RESTORE_LOG_DIRECTORY_PATH is empty or the directory does not exists or the directory permissions are wrong!"
        log_info "Creating log directory at ${RESTORE_LOG_DIRECTORY_PATH}."
        if ! create_directory "${RESTORE_LOG_DIRECTORY_PATH}"; then
            log_error "Failed to create log directory!"
            exit 1
        fi
    fi

    

    # Validate config

    validate_config_value "LOCAL_REPOSITORY_PATH"
    local LOCAL_REPOSITORY_PATH="$(get_config_value "LOCAL_REPOSITORY_PATH")"
    if ! validate_directory "${LOCAL_REPOSITORY_PATH}" ; then
        log_error "The LOCAL_REPOSITORY_PATH does not exists or the directory permissions are wrong!"
        # commented out because the dev environment filesystem permission limitations
        exit 1
    fi

    if validate_optional_config_value "DEBUG_LOG"; then
        local debug_log_val
        
        debug_log_val=$(get_config_value "DEBUG_LOG")

        if is_var_equals "${debug_log_val}" "true" || is_var_equals "${debug_log_val}" "false" ; then
            DEBUG_LOG="${debug_log_val}"
        else
            log_warn "Invalid value in config for key: DEBUG_LOG" 
        fi
    fi

    validate_config_value "REMOTE_REPOSITORY_PATH"
    validate_config_value "BACKBLAZE_B2_ACCOUNT_ID"
    validate_config_value "BACKBLAZE_B2_ACCOUNT_KEY"
    validate_config_value "HEALTHCHECKS_IO_ID"
    validate_config_value "GOTIFY_SERVER_URL"
    validate_config_value "GOTIFY_SERVER_TOKEN"
    validate_config_value "KOPIA_REPOSITORY_PASSWORD"
    validate_config_value "RESTIC_REPOSITORY_PASSWORD"
    validate_config_value "LOG_VIEWER_ADDRESS"
    validate_config_value "WEBDAV_LISTEN_ADDRESS"
    validate_config_value "HOT_BACKUP_FREQUENCY"
    validate_config_value "COLD_BACKUP_FREQUENCY"
    validate_config_value "RETENTION_KEEP_YEARLY"
    validate_config_value "RETENTION_KEEP_MONTHLY"
    validate_config_value "RETENTION_KEEP_WEEKLY"
    validate_config_value "RETENTION_KEEP_DAILY"
    validate_config_value "RETENTION_KEEP_HOURLY"
    validate_config_value "RETENTION_KEEP_LAST"
}

# Print usage infromation
function print_help() {
    local commands="$*"
    log_info "Usage: ${SCRIPT_BASE_NAME} $(echo "${commands[*]}" | tr ' ' '\|')"
}

# Print usage infromation
function print_sub_help() {
    local command="$1"; shift
    local commands="$*"
    log_info "Usage: ${SCRIPT_BASE_NAME} ${command} $(echo "${commands[*]}" | tr ' ' '\|')"
}

# Check if string is elemnt of array
function is_in_array() {
    local string="$1"; shift
    local array="$*"

    if [[ " ${array[*]} " =~ ${string} ]]; then
        return 0
    fi

    return 1
}

# Check if the command in the first argument is in the array recevied as the other arguments
function is_valid_command() {
    local command="$1"; shift
    local commands="$*"

    if is_var_empty "${command}"; then
        return 1
    fi

    if is_in_array "${command}" "${commands}"; then
        return 0
    else
        return 1
    fi
}

function validate_repository_type() {
    local type="$1"

    if is_var_equals "local" "${type}" || is_var_equals "remote" "${type}"; then
        return 0
    else
        log_error "Invalid repository type!"
        return 1
    fi
}

function update_client_list() {
    log_info "Downloading clients file list."
    wget --quiet "${ONLINE_CLIENTS_FILE_URL}" -O "${CLIENTS_FILE_PATH}"
    chmod 600 "${CLIENTS_FILE_PATH}"
}

# Call print_help funtion to print usage infromation
function help() {
    print_help "${COMMANDS[*]}"
}

# Init local kopia repository
function repo_init_local() {
    local repository_path 
    local repository_password
    repository_path=$(get_config_value "LOCAL_REPOSITORY_PATH")
    repository_password=$(get_config_value "KOPIA_REPOSITORY_PASSWORD")

    log_info "Initialize kopia repository at ${repository_path}."
    kopia repository create filesystem --ecc-overhead-percent=10 --password="${repository_password}" --path="${repository_path}" 2>&1 | log_harvest
    kopia policy set --global --compression=zstd-fastest 2>&1 | log_harvest
}

# Init remote restic repository
function repo_init_remote() {
    local repository_path 
    local repository_password
    repository_path=$(get_config_value "REMOTE_REPOSITORY_PATH")
    repository_password=$(get_config_value "RESTIC_REPOSITORY_PASSWORD")

    RESTIC_REPOSITORY="${repository_path}" RESTIC_PASSWORD="${repository_password}" restic --verbose init 2>&1 | log_harvest
}

# Init backup repository
function repo_init() {
    local type="$1"; shift

    validate_repository_type "${type}" && \
    repo_init_"${type}" "$*"
}

# Repository manipulating
function repo() {
    local subcommand="$1"; shift
    
    if is_valid_command "${subcommand}" "${REPO_COMMANDS[*]}"; then
        repo_"${subcommand}" "$@"
    else
        print_sub_help "repo" "${REPO_COMMANDS[*]}"
        exit 1
    fi
}

# List local kopia repository snapshots
function snap_list_local() {
    local username="$1"; shift
    local hostname="$1"; shift
    local tag="$1"; shift
    local additional_params

    if is_var_not_empty "${username}" && is_var_not_empty "${hostname}"; then
        local repository_path 
        local repository_password
        repository_path=$(get_config_value "LOCAL_REPOSITORY_PATH")
        repository_password=$(get_config_value "KOPIA_REPOSITORY_PASSWORD")
        kopia repository connect filesystem --password="${repository_password}" --path="${repository_path}" --override-username="${username}" --override-hostname="${hostname}" 2>&1 | log_harvest
    else
        additional_params="--all"
    fi

    if is_var_not_empty "${tag}"; then
        additional_params="--tags=${tag}:${tag}"
    elif is_var_not_empty "${username}" && is_var_empty "${hostname}"; then
        tag="${username}"
        username=""
        additional_params="${additional_params} --tags=${tag}:${tag}"
    fi

    # shellcheck disable=SC2086
    kopia snapshot list ${additional_params} 2>&1 | log_harvest
}

# List remote restic repository snapshots
function snap_list_remote() {
    local username="$1"; shift
    local hostname="$1"; shift
    local tag="$1"; shift
    local additional_params
    local repository_path 
    local repository_password
    repository_path=$(get_config_value "REMOTE_REPOSITORY_PATH")
    repository_password=$(get_config_value "RESTIC_REPOSITORY_PASSWORD")

    if is_var_not_empty "${username}" && is_var_not_empty "${hostname}"; then
        additional_params="--host ${hostname}"
    fi

    if is_var_not_empty "${tag}"; then
        additional_params="--tag=${tag}"
    elif is_var_not_empty "${username}" && is_var_empty "${hostname}"; then
        tag="${username}"
        username=""
        additional_params="${additional_params} --tag=${tag}"
    fi

    # shellcheck disable=SC2086
    RESTIC_REPOSITORY="${repository_path}" RESTIC_PASSWORD="${repository_password}" restic --verbose snapshots ${additional_params} 2>&1 | log_harvest
}

# List all snapshots
function snap_list() {
    local type="$1"; shift
    local username="$1"; shift
    local hostname="$1"; shift
    local tag="$1"; shift

    validate_repository_type "${type}" && \
    snap_list_"${type}" "${username}" "${hostname}" "${tag}" "$*"
}

# Create local kopia snapshot
function snap_create_local() {
    local username="$1"; shift
    local hostname="$1"; shift
    local tag="$1"; shift
    local source="$1"; shift
    local repository_path 
    local repository_password
    repository_path=$(get_config_value "LOCAL_REPOSITORY_PATH")
    repository_password=$(get_config_value "KOPIA_REPOSITORY_PASSWORD")
    
    kopia repository connect filesystem --password="${repository_password}" --path="${repository_path}" --override-username="${username}" --override-hostname="${hostname}" > /dev/null 2>&1 && \
    kopia snapshot create --no-progress --tags="${tag}:${tag}" "${source}" 2>&1 | log_harvest
}

# Create remote restic snapshot
function snap_create_remote() {
    local username="$1"; shift
    local hostname="$1"; shift
    local tag="$1"; shift
    local source="$1"; shift
    local repository_path 
    local repository_password
    repository_path=$(get_config_value "REMOTE_REPOSITORY_PATH")
    repository_password=$(get_config_value "RESTIC_REPOSITORY_PASSWORD")

    RESTIC_REPOSITORY="${repository_path}" RESTIC_PASSWORD="${repository_password}" restic backup --one-file-system --ignore-inode --ignore-ctime --no-scan "${source}" --tag "${tag}" --host "${hostname}"  2>&1 | log_harvest
}

# Create snapshot
function snap_create() {
    local type="$1"; shift
    local username="$1"; shift
    local hostname="$1"; shift
    local tag="$1"; shift
    local source="$1"; shift

    if is_var_empty "${type}" || is_var_empty "${username}" || is_var_empty "${hostname}" || is_var_empty "${tag}" || is_var_empty "${source}"; then
        log_info "Usage: ${SCRIPT_BASE_NAME} snap create local|remote username hostname tag source"
        return 1
    fi

    validate_repository_type "${type}" && \
    snap_create_"${type}" "${username}" "${hostname}" "${tag}" "${source}" "$*"
}

# Restore local kopia snapshot
function snap_restore_local() {
    local username="$1"; shift
    local hostname="$1"; shift
    local id="$1"; shift
    local destination="$1"; shift
    local repository_path 
    local repository_password
    repository_path=$(get_config_value "LOCAL_REPOSITORY_PATH")
    repository_password=$(get_config_value "KOPIA_REPOSITORY_PASSWORD")
    
    kopia repository connect filesystem --password="${repository_password}" --path="${repository_path}" --override-username="${username}" --override-hostname="${hostname}" > /dev/null 2>&1 && \
    kopia snapshot restore --no-progress "${id}" "${destination}" 2>&1 | log_harvest
}

# Restore remote restic snapshot
function snap_restore_remote() {
    local username="$1"; shift
    local hostname="$1"; shift
    local id="$1"; shift
    local destination="$1"; shift
    local repository_path 
    local repository_password
    repository_path=$(get_config_value "REMOTE_REPOSITORY_PATH")
    repository_password=$(get_config_value "RESTIC_REPOSITORY_PASSWORD")

    RESTIC_REPOSITORY="${repository_path}" RESTIC_PASSWORD="${repository_password}" restic restore "${id}":"${destination}" --host "${hostname}" --target "${destination}" --verify 2>&1 | log_harvest
}

# Restore snapshot
function snap_restore() {
    local type="$1"; shift
    local username="$1"; shift
    local hostname="$1"; shift
    local id="$1"; shift
    local destination="$1"; shift

    if is_var_empty "${type}" || is_var_empty "${username}" || is_var_empty "${hostname}" || is_var_empty "${id}" || is_var_empty "${destination}"; then
        log_info "Usage: ${SCRIPT_BASE_NAME} snap restore local|remote username hostname id destination"
        return 1
    fi

    validate_repository_type "${type}" && \
    snap_restore_"${type}" "${username}" "${hostname}" "${id}" "${destination}" "$*"
}

# Delete local kopia snapshot
function snap_delete_local() {
    local id="$1"; shift
    local dry_run_result
    local answer

    kopia snapshot delete "${id}" 2>&1 | log_harvest
    dry_run_result=${PIPESTATUS[0]}
    if [ "${dry_run_result}" -gt 0 ]; then
        return 0
    fi

    log_input "Do you wish to delete the snapshots listed above? (yes/no): "
    read -r -p "" answer
    if is_var_equals "${answer}" "yes"; then
        kopia snapshot delete --delete "${id}" 2>&1 | log_harvest
    else 
        log_warn "Bad answer! Proceeding without deleting snapshots."
        return 0
    fi
}

# Delete remote restic snapshot
function snap_delete_remote() {
    local id="$1"; shift
    local dry_run_result
    local answer
    local repository_path
    local repository_password
    repository_path=$(get_config_value "REMOTE_REPOSITORY_PATH")
    repository_password=$(get_config_value "RESTIC_REPOSITORY_PASSWORD")

    RESTIC_REPOSITORY="${repository_path}" RESTIC_PASSWORD="${repository_password}" restic snapshots "${id}" 2>&1 | log_harvest
    dry_run_result=${PIPESTATUS[0]}
    if [ "${dry_run_result}" -gt 0 ]; then
        return 0
    fi

    log_input "Do you wish to delete the snapshots listed above? (yes/no): "
    read -r -p "" answer
    if is_var_equals "${answer}" "yes"; then
        RESTIC_REPOSITORY="${repository_path}" RESTIC_PASSWORD="${repository_password}" restic forget "${id}" 2>&1 | log_harvest
    else 
        log_warn "Bad answer! Proceeding without deleting snapshots."
        return 0
    fi
}

# Delete snapshot
function snap_delete() {
    local type="$1"; shift
    local id="$1"; shift

    if is_var_empty "${type}" ||  is_var_empty "${id}"; then
        log_info "Usage: ${SCRIPT_BASE_NAME} snap delete local|remote id"
        return 1
    fi

    validate_repository_type "${type}" && \
    snap_delete_"${type}" "${id}" "$*"
}

# Snapshot create/restore/delete
function snap() {
    local subcommand="$1"; shift
    
    if is_valid_command "${subcommand}" "${SNAP_COMMANDS[*]}"; then
        snap_"${subcommand}" "$@"
    else
        print_sub_help "snap" "${SNAP_COMMANDS[*]}"
        exit 1
    fi
}

# Backup job and repository status
function status() {
    log_error "Not implemented!"
}

function get_remote_user() {
    local client="$1"
    echo "${client}" | cut -d ";" -f 1
}

function get_remote_host() {
    local client="$1"
    echo "${client}" | cut -d ";" -f 2
}

function get_remote_path() {
    local client="$1"
    echo "${client}" | cut -d ";" -f 3
}

function get_mount_path() {
    local client="$1"
    local remote_host
    local remote_path

    remote_host=$(get_remote_host "${client}")
    remote_path=$(get_remote_path "${client}")

    local local_base_path="${MOUNT_DIRECTORY_PATH}"
    local mount_path="${local_base_path}/${remote_host}${remote_path}"

    echo "${mount_path}"
}

function gen_tag_from_client() {
    local client="$1"

    echo "${client}" | awk -F";" '{print $1"@"$2}'
}

function manage_docker() {
    local client="$1"
    local operation="$2"
    local user
    local host
    
    user=$(get_remote_user "${client}")
    host=$(get_remote_host "${client}")

    if is_var_equals "${operation}" "start"; then
        local start_docker_socket_result
        local start_docker_service_result
        local start_containerd_service_result
        
        log_info "Starting docker services on client: ${client}"

        ssh -n "${user}"@"${host}" "systemctl start containerd.service" 2>&1 | log_harvest
        start_containerd_service_result=${PIPESTATUS[0]}
        ssh -n "${user}"@"${host}" "systemctl start docker.service" 2>&1 | log_harvest
        start_docker_service_result=${PIPESTATUS[0]}
        ssh -n "${user}"@"${host}" "systemctl start docker.socket" 2>&1 | log_harvest
        start_docker_socket_result=${PIPESTATUS[0]}

        if [ "${start_docker_socket_result}" -eq 0 ] && [ "${start_docker_service_result}" -eq 0 ] && [ "${start_containerd_service_result}" -eq 0 ]; then
            log_info "Docker services started successfully on client: ${client}"
            return 0
        else
            log_error "Failed to start docker services on client: ${client}"
            return 1
        fi
    fi

    if is_var_equals "${operation}" "stop"; then
        local stop_docker_socket_result
        local stop_docker_service_result
        local stop_containerd_service_result

        log_info "Stopping docker services on client: ${client}"

        ssh -n "${user}"@"${host}" "systemctl stop docker.socket" 2>&1 | log_harvest
        stop_docker_socket_result=${PIPESTATUS[0]}
        ssh -n "${user}"@"${host}" "systemctl stop docker.service" 2>&1 | log_harvest
        stop_docker_service_result=${PIPESTATUS[0]}
        ssh -n "${user}"@"${host}" "systemctl stop containerd.service" 2>&1 | log_harvest
        stop_containerd_service_result=${PIPESTATUS[0]}

        if [ "${stop_docker_socket_result}" -eq 0 ] && [ "${stop_docker_service_result}" -eq 0 ] && [ "${stop_containerd_service_result}" -eq 0 ]; then
            log_info "Docker services stopped successfully on client: ${client}"
            return 0
        else
            log_error "Failed to stop docker services on client: ${client}"
            return 1
        fi
    fi

    return 1
}

# Mount client fs
function mount_client() {
    local client="$1"; shift
    local remote_user
    local remote_host
    local remote_path
    local mount_path

    remote_user=$(get_remote_user "${client}")
    remote_host=$(get_remote_host "${client}")
    remote_path=$(get_remote_path "${client}")
    mount_path=$(get_mount_path "${client}")

    if ! is_directory_exists "${mount_path}"; then
        if ! mkdir -p "${mount_path}" > /dev/null 2>&1; then
            log_error "Failed to create directory at ${mount_path}"
            return 1
        fi
    fi

    if is_directory_mounted "${mount_path}"; then
        log_warn "Client already mounted: ${client}"
        return 1
    fi

    log_info "Mounting client '${client}' filesystem."

    rm -f ~/.ssh/known_hosts > /dev/null 2>&1
    touch ~/.ssh/known_hosts > /dev/null 2>&1

    if ssh-keyscan -t ssh-ed25519 "${remote_host}" 2> /dev/null >> ~/.ssh/known_hosts && \
        sshfs -o "${SSHFS_OPTIONS}" "${remote_user}@${remote_host}:${remote_path}" "${mount_path}" > /dev/null 2>&1 && \
        is_directory_exists "${mount_path}" && \
        is_directory_mounted "${mount_path}"; then
        log_info "Client '${client}' filesystem successfully mounted!"
        return 0
    else
        log_error "Failed to mount client filesystem: ${client}"
        return 1
    fi
}

# Unmount client fs
function unmount_client() {
    local client="$1"; shift
    local mount_path
    mount_path=$(get_mount_path "${client}")
    
    log_info "Unmounting client '${client}' filesystem."

    if is_directory_exists "${mount_path}" && is_directory_mounted "${mount_path}"; then
        if umount "${mount_path}"; then
            log_info "Client '${client}' filesystem successfully unmounted!"
        else
            log_error "Failed to mount client filesystem: ${client}"
        fi
    else 
        log_error "Client does not mounted: ${client}"
    fi
}

# Backup client
function backup_client() {
    local client="$1"
    local type="$2"
    local username
    local hostname
    local tag
    local source

    username=$(get_remote_user "${client}")
    hostname=$(get_remote_host "${client}")
    source=$(get_mount_path "${client}")
    tag="$(gen_tag_from_client "${client}")+${type}"

    log_info "Starting backup for client '${client}'"

    if is_host_up "${hostname}"; then
        local connection

        log_info "Checking connection with client '${client}'."
        tailscale ping -c 3 "${hostname}" 2>&1 | log_harvest

        connection=$(tailscale status | grep "${hostname}" | awk '{print $5 $6}')

        log_result "[host: ONLINE ] "

        if is_var_equals "${connection}" "active;direct"; then
            log_result "[connection: DIRECT] "
        elif is_var_equals "${connection}" "active;relay"; then
            log_result "[connection: RELAY ] "
        else
            log_result "[connection: ERROR ] "
        fi
    else
        log_result "[host: OFFLINE] "
        log_result "[connection: ERROR ] "
        log_result "[local: FAILED] "
        log_result "[remote: FAILED] "

        log_error "Failed to create local backup for client '${client}'"
        log_error "The client is offline."
        return 1
    fi

    # mount sshfs
    if ! mount_client "${client}"; then
        log_result "[local: FAILED] "
        log_result "[remote: FAILED] "
        return 1
    fi

    if is_var_equals "${type}" "cold"; then
        manage_docker "${client}" "stop"
    fi

    local local_backup_result
    local remote_backup_result

    # create local backup
    log_info "Starting local backup for client '${client}'"
    if snap_create_local "${username}" "${hostname}" "${tag}" "${source}"; then
        log_info "Local backup successfully created for client '${client}'"
        log_result "[local:   OK  ] "
        local_backup_result=0
    else
        log_error "Failed to create local backup for client '${client}'"
        log_result "[local: FAILED] "
        local_backup_result=1
    fi
    
    # create remote backup
    log_info "Starting remote backup for client '${client}'"
    if snap_create_remote "${username}" "${hostname}" "${tag}" "${source}"; then
        log_info "Remote backup successfully created for client '${client}'"
        log_result "[remote:   OK  ] "
        remote_backup_result=0
    else
        log_error "Failed to create remote backup for client '${client}'"
        log_result "[remote: FAILED] "
        remote_backup_result=1
    fi

    
    if is_var_equals "${type}" "cold"; then
        manage_docker "${client}" "start"
    fi

    # umount sshfs
    unmount_client "${client}"

    if [ "${local_backup_result}" -gt 0 ] || [ "${remote_backup_result}" -gt 0 ]; then
        return 1
    fi

    return 0
}

# Run hot backup
function backup_hot() {
    local total
    local count
    local backup_overall_status=0
    
    total=$(cat "${CLIENTS_FILE_PATH}" | wc -l)
    total=$((total+1))
    count=1

    log_result "Number of backup clients: ${total}"; log_result_end
    log_result_footer
    
    while IFS= read -r client || [ -n "${client}" ]
    do
        log_info "***************************************************************************************"
        log_info "Starting hot backup of client ${client}. [${count}/${total}]"
        log_info "***************************************************************************************"
        log_result "Client: ${client} "; log_result_end
        if backup_client "${client}" "hot"; then
            log_result "[overall:   OK  ]"
        else
            log_result "[overall: FAILED]"
            backup_overall_status=1
        fi
        log_result_end
        count=$((count+1))
    done < "${CLIENTS_FILE_PATH}"

    return ${backup_overall_status}
}

# Run cold backup
function backup_cold() {
    local total
    local count
    local backup_overall_status=0

    total=$(cat "${CLIENTS_FILE_PATH}" | wc -l)
    total=$((total+1))
    count=1

    log_result "Client count: ${total}"; log_result_end

    while IFS= read -r client || [ -n "${client}" ]
    do
        log_info "***************************************************************************************"
        log_info "Starting cold backup of client ${client}. [${count}/${total}]"
        log_info "***************************************************************************************"
        log_result "Client: ${client} "; log_result_end
        if backup_client "${client}" "cold"; then
            log_result "[overall:   OK  ]"
        else
            log_result "[overall: FAILED]"
            backup_overall_status=1
        fi
        log_result_end
        count=$((count+1))
    done < "${CLIENTS_FILE_PATH}"

    return ${backup_overall_status}
}

function prune() {
    local local_repository_path
    local local_repository_password
    local remote_repository_path
    local remote_repository_password
    local local_repository_prune_result
    local remote_repository_prune_result

    local_repository_path=$(get_config_value "LOCAL_REPOSITORY_PATH")
    local_repository_password=$(get_config_value "KOPIA_REPOSITORY_PASSWORD")
    remote_repository_path=$(get_config_value "REMOTE_REPOSITORY_PATH")
    remote_repository_password=$(get_config_value "RESTIC_REPOSITORY_PASSWORD")

    log_info "Removed expired snapshots from local repository."
    kopia repository connect filesystem --password="${local_repository_path}" --path="${local_repository_password}" > /dev/null 2>&1 && \
    kopia snapshot expire --all 2>&1 | log_harvest
    local_repository_prune_result=${PIPESTATUS[0]}

    log_info "Removed expired snapshots from remote repository."
    RESTIC_REPOSITORY="${remote_repository_path}" RESTIC_PASSWORD="${remote_repository_password}" restic forget \
    --keep-yearly "$(get_config_value "RETENTION_KEEP_YEARLY")" \
    --keep-monthly "$(get_config_value "RETENTION_KEEP_MONTHLY")" \
    --keep-weekly "$(get_config_value "RETENTION_KEEP_WEEKLY")" \
    --keep-daily "$(get_config_value "RETENTION_KEEP_DAILY")" \
    --keep-hourly "$(get_config_value "RETENTION_KEEP_HOURLY")" \
    --keep-last "$(get_config_value "RETENTION_KEEP_LAST")" \
    --prune 2>&1 | log_harvest
    remote_repository_prune_result=${PIPESTATUS[0]}

    if [ "${local_repository_prune_result}" -gt 0 ] || [ "${remote_repository_prune_result}" -gt 0 ]; then
        return 1
    fi

    return 0
}

# Backup clients
function backup() {
    local type="$1"; shift
    local general_log_file_path
    local backup_log_file_path
    local result_file_path

    if [[ -t 0 ]] && [[ -f "/etc/systemd/system/${HOT_BACKUP_SCRIPT_SERVICE_NAME}.service" ]]; then
        ## Run by triggering the systemd unit, so everything gets logged:
        trigger_hot_backup
        return 0
    fi

    if [[ -t 0 ]] && [[ -f "/etc/systemd/system/${COLD_BACKUP_SCRIPT_SERVICE_NAME}.service" ]]; then
        ## Run by triggering the systemd unit, so everything gets logged:
        trigger_cold_backup
        return 0
    fi

    if ! is_var_equals "${type}" "cold" && ! is_var_equals "${type}" "hot"; then
        log_error "Invalid backup type! Possible values: hot|cold"
        return 1
    fi

    update_client_list

    if [ "$(cat "${CLIENTS_FILE_PATH}" | wc -l)" -eq 0 ]; then
        log_warn "The CLIENT_FILE '${CLIENTS_FILE_PATH}' is empty!"
        return 0
    fi

    ping_healthchecks_io "start"

    log_result_header
    log_result "Backup type: ${type}"; log_result_end
    if ! backup_"${type}"; then
        log_result_footer
        ping_healthchecks_io "error"
        send_gotify_notification "Backup FAILED" "$(get_config_value "LOG_VIEWER_ADDRESS")/${BACKUP_LOG_FILE_NAME}"
    fi
    log_result_footer

    prune

    ping_healthchecks_io "stop"
    
    result_file_path=${RESULT_FILE_PATH}
    general_log_file_path="${LOG_FILE_PATH}"
    backup_log_file_path="${BACKUP_LOG_DIRECTORY_PATH}/${BACKUP_LOG_FILE_NAME}"

    mv "${result_file_path}" "${backup_log_file_path}"
    cat "${general_log_file_path}" >> "${backup_log_file_path}"

    systemctl restart "${RCLONE_WEBDAV_SERIVCE_NAME}"
}

function restore_client() {
    local client="$1"
    local type="$2"
    local username="$3"
    local hostname="$4"
    local id="$5"
    local destination="$6"

    if mount_client "${client}"; then
        if snap_restore "${type}" "${username}" "${hostname}" "${id}" "${destination}"; then
            log_info "Client successfully restored!"
        else
            log_error "Restore failed!"
        fi
        unmount_client "${client}"
    else
        log_error "Restore failed! Could not mount client filesystem!"
        exit 1
    fi
}

function restore() {
    local source
    local type
    local selected_client
    local tag
    local username
    local hostname
    local snapshot
    local destination
    local answer
    local general_log_file_path
    local restore_log_file_path

    log_warn "The restoring process will delete/overwrite any existing data on the restore path!"

    log_input "Which source would like to use (local/remote): "
    read -r -p "" source
    if ! is_var_equals "${source}" "local" && ! is_var_equals "${source}" "remote"; then
        log_error "Invalid restore source!"
        exit 1
    fi

    log_input "Select snapshot type (hot/cold): "
    read -r -p "" type
    if ! is_var_equals "${type}" "hot" && ! is_var_equals "${type}" "cold"; then
        log_error "Invalid snapshot type!"
        exit 1
    fi

    log_info "Please select from the following list:"
    local counter=1
    while IFS= read -r client || [ -n "${client}" ]
    do
        log_info "[${counter}] ${client}"
        counter=$((counter+1))
    done < "${CLIENTS_FILE_PATH}"

    log_input "Client number: "
    read -r -p "" client_id
    if [ "${client_id}" -ge ${counter} ]; then
        log_error "Invalid client number!"
        exit 1
    fi

    local iter=1  
    while IFS= read -r client || [ -n "${client}" ]
    do
        if [ "${iter}" -eq "${client_id}" ]; then
            log_info "Selected client: ${client}"
            selected_client="${client}"
        fi
        iter=$((iter+1))
    done < "${CLIENTS_FILE_PATH}"

    username=$(get_remote_user "${selected_client}")
    hostname=$(get_remote_host "${selected_client}")
    destination=$(get_mount_path "${selected_client}")
    tag=$(gen_tag_from_client "${selected_client}")+"${type}"

    snap_list "${source}" "${username}" "${hostname}" "${tag}"

    log_input "Enter the snapshot id: "
    read -r -p "" snapshot

    if ! snap_list "${source}" "${username}" "${hostname}" "${tag}" | grep ${snapshot} > /dev/null 2>&1; then
        log_error "Invalid snapshot!"
        exit 1
    fi

    log_info "***************************************************************************************"
    log_info "Please check the following info before you proceed to the restore!"
    log_info "***************************************************************************************"
    log_info "Repository:    ${source}"
    log_info "Snapshot type: ${type}"
    log_info "Client:        ${selected_client}"
    log_info "Username:      ${username}"
    log_info "Hostname:      ${hostname}"
    log_info "Destination:   ${destination}"
    log_info "Tag:           ${tag}"
    log_info "Snapshot id:   ${snapshot}"
    log_info "***************************************************************************************"
    log_warn "Please be aware that the restoring process will overwrite the data at the destination path!"
    log_input "Would you like to restore the snapshot? (yes/no): "
    read -r -p "" answer

    if is_var_equals "${answer}" "yes"; then
        restore_client "${selected_client}" "${source}" "${username}" "${hostname}" "${snapshot}" "${destination}"
    elif is_var_equals "${answer}" "no"; then
        log_info "Exiting without any modification to the client!"
        return 0
    else
        log_error "Invalid answer!"
        return 1
    fi

    general_log_file_path="${LOG_FILE_PATH}"
    restore_log_file_path="${RESTORE_LOG_DIRECTORY_PATH}/$(echo "${LOG_FILE_NAME}" | tr -d '.log')-restore.log"
    cp "${general_log_file_path}" "${restore_log_file_path}"

    return 0
}

function trigger_hot_backup() {
    (set -x; systemctl start "${HOT_BACKUP_SCRIPT_SERVICE_NAME}".service)
    log_info "systemd is now running the restia hot backup job in the background. Check 'status' later."
}

function trigger_cold_backup() {
    (set -x; systemctl start "${COLD_BACKUP_SCRIPT_SERVICE_NAME}".service)
    log_info "systemd is now running the restia cold backup job in the background. Check 'status' later."
}

function init() {

    if ! is_sshfs_installed; then
        log_error "Could not find sshfs binary on this system. Please install it before running this script!"
        return 1
    fi

    if ! is_restic_installed; then
        log_error "Could not find restic binary on this system. Please install it before running this script!"
        return 1
    fi

    if ! is_kopia_installed; then
        log_error "Could not find kopia binary on this system. Please install it before running this script!"
        return 1
    fi


    # calidate consts and config values
    validate_config
}

function main() {
    if test $# = 0; then
        print_help "${COMMANDS[*]}"
        exit
    fi

    local command="$1"; shift

    if is_valid_command "${command}" "${COMMANDS[*]}"; then
        "${command}" "$@"
    else
        log_error "Unknown command: ${command}"
        log_info "Run '${SCRIPT_BASE_NAME} help' to see how can you use this backup script!"
        exit 1
    fi

    return 0
}

init && main "$@"