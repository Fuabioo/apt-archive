#!/bin/bash
set -e

# force bash for the execution (should avoid issues on codespaces and executing from non-bash shells)
if [ -z "$BASH_VERSION" ]; then
  exec bash "$0" "$@"
fi

terminal_width=$(tput cols || 80)

# Reset
NoColor=''

# Regular Colors
Red=''
Green=''
Magenta=''
Cyan=''
Yellow=''
Dim='' # White

# Bold
BoldWhite=''
Bold_Green=''
BoldMagenta=''

if [[ -t 1 ]]; then
    # Reset
    NoColor='\033[0m' # Text Reset

    # Regular Colors
    Red='\033[0;31m'
    Green='\033[0;32m'
    Magenta='\033[35m'
    Cyan='\033[36m'
    Yellow='\033[0;33m'
    Dim='\033[0;2m'    # White

    BoldMagenta='\033[1;35m'
    BoldWhite='\033[1m'
fi

LOG_LEVEL=${LOG_LEVEL:-INFO}

divider() {
    printf "${Dim}%${terminal_width}s${NoColor}\n" | tr ' ' '-'
}
log() {
    local level=$1
    shift
    local levelColor=$1
    shift
    echo -e "$(date +%Y-%m-%dT%H:%M:%S%z) ${levelColor}${level}${NoColor} $@"
}
debug() {
    if [ "$LOG_LEVEL" = "DEBUG" ]; then
        log 'DBG' $Magenta $@
    fi
}
error() {
    log 'ERR' ${Red} "$@" >&2; exit 1
}
info() {
    log 'INF' $Cyan $@
}
warning() {
    log 'WRN' $Yellow "${BoldWhite}$@ ${NoColor}"
}
success() {
    log 'OK!' $Green $@
}

export DEBIAN_FRONTEND=noninteractive

info "Before adding, updating official packages"
apt update -qq && apt upgrade -qq -y

debug "Executing cleanup of previous runs"
if [ -d dists ]; then
    rm -r dists
fi
if [ -d pool ]; then
    rm -r pool
fi

divider

info "Setting up ephemeral GPG environment variables"
source /usr/local/bin/set-gpg-env.sh

info "Loading GPG profile"
scripts/load-gpg-profile.sh

info "Using specs to generate .deb packages"
for f in specs/*.yml; do
    debug "Generating .deb for $f"
    bash scripts/wrap-to-deb.sh "$f"
done

info "Building APT repository"
bash scripts/build-repo.sh

divider

debug "Preparing test HTTPS server"
cp -r dists /usr/share/nginx/html/dists
cp -r pool /usr/share/nginx/html/pool
cp public.gpg /usr/share/nginx/html/public.gpg

debug "Generating nginx 443 configuration"
rm /etc/nginx/sites-enabled/default
echo 'server {
    listen 443 ssl;
    server_name localhost;

    ssl_certificate /etc/nginx/certs/localhost.pem;
    ssl_certificate_key /etc/nginx/certs/localhost-key.pem;

    location / {
        root /usr/share/nginx/html;  # Default nginx root
        index index.html index.htm;
    }
}
' >> /etc/nginx/sites-enabled/default

debug "Starting up nginx server"
nginx &

wait() {
    MAX_RETRIES=15
    SLEEP_INTERVAL=1
    count=0
    while ! curl -s https://localhost > /dev/null; do
    ((count++))
    if [ "$count" -ge "$MAX_RETRIES" ]; then
        echo "nginx failed to start after $MAX_RETRIES retries."
        exit 1
    fi
    sleep $SLEEP_INTERVAL
    done
    exit 0
}

info "Verifying test HTTPS APT respository server is healthy"
(wait && debug "up") || fatal "nel"

divider

info "Adding custom APT to testing runtime (doesn't require sudo)"
debug "curl -fsSL https://localhost/public.gpg | tee /usr/share/keyrings/apt.fuabioo.gpg > /dev/null"
curl -fsSL https://localhost/public.gpg | tee /usr/share/keyrings/apt.fuabioo.gpg > /dev/null
debug "echo "deb [signed-by=/usr/share/keyrings/apt.fuabioo.gpg] https://localhost stable main" | tee /etc/apt/sources.list.d/apt.fuabioo.list"
echo "deb [signed-by=/usr/share/keyrings/apt.fuabioo.gpg] https://localhost stable main" | tee /etc/apt/sources.list.d/apt.fuabioo.list

divider

info "After adding, updating packages and installing dontrm"
apt update && apt install dontrm

info "Verifying repository by installing and executing one package"
command="dontrm version"
echo $command
eval $command

info "Installing fastfetch to verify external pre-built .deb package"
apt install fastfetch

info "Verifying repository by installing and executing one package"
command="fastfetch"
echo $command
eval $command
