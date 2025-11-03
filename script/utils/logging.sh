#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

debug() {
    if [ "${DEBUG}" = "true" ]; then
        echo -e "${BLUE}[DEBUG]${NC} $1"
    fi
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

info() {
    echo -e "${CYAN}[INFO]${NC} $1"
}

step() {
    echo -e "${PURPLE}[STEP]${NC} $1"
}


separator() {
    echo "=================================================="
}


header() {
    local title="$1"
    echo ""
    separator
    echo -e "${BLUE}${title}${NC}"
    separator
    echo ""
}


footer() {
    echo ""
    separator
    echo ""
}
