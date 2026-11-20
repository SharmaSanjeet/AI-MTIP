#!/bin/bash

# AI-MTIP Linux Startup Script
# Resolves repository paths dynamically so it can be executed from any working directory.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
BACKEND_DIR="$REPO_ROOT/backend"

echo "Starting AI-MTIP on Linux..."
echo "Repository root: $REPO_ROOT"

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is not installed. Please install Python 3."
    exit 1
fi

# Check if pip is installed
if ! command -v pip3 &> /dev/null && ! python3 -m pip --version &> /dev/null; then
    echo "Warning: pip3 is not installed. You may need it to install dependencies."
fi

# Parse CLI arguments
MTIP_MODE=""
MTIP_RECONFIG=""
for arg in "$@"; do
    case "$arg" in
        --server|-s)
            MTIP_MODE="server"
            ;;
        --workstation|-w)
            MTIP_MODE="workstation"
            ;;
        --setup|--reconfigure)
            MTIP_RECONFIG=1
            ;;
    esac
done

# Navigate to backend directory
cd "$BACKEND_DIR"

# Create virtual environment if it doesn't exist
if [ ! -d "venv" ]; then
    echo "Creating virtual environment in $BACKEND_DIR/venv..."
    python3 -m venv venv
fi

# Activate virtual environment
source venv/bin/activate

# Ensure Python can resolve modules from repo root as well as backend
export PYTHONPATH="$REPO_ROOT:$BACKEND_DIR:${PYTHONPATH:-}"

# Install dependencies from root requirements.txt
echo "Installing backend dependencies from $REPO_ROOT/requirements.txt..."
if [ -f "$REPO_ROOT/requirements.txt" ]; then
    pip install -r "$REPO_ROOT/requirements.txt"
elif [ -f "$BACKEND_DIR/requirements.txt" ]; then
    pip install -r "$BACKEND_DIR/requirements.txt"
else
    echo "Error: requirements.txt not found!"
    exit 1
fi

# Prompt for deployment mode if unset
EXISTING_MODE=$(python3 -c "import deployment_config; print(deployment_config.get_deployment_mode())" 2>/dev/null || echo "workstation")

if [ -n "$MTIP_RECONFIG" ] || { [ -z "$MTIP_MODE" ] && ! grep -q "^MTIP_MODE=" "$REPO_ROOT/.env" 2>/dev/null; }; then
    if [ -t 0 ]; then
        echo ""
        echo "======================================================================"
        echo "  AI-MTIP Deployment Mode Selection"
        echo "======================================================================"
        echo "  [1] Workstation Mode  (Local desktop)"
        echo "  [2] Team Server Mode  (Shared server, auto-discovery, web staging)"
        echo "======================================================================"
        read -r -p "Select mode [1 or 2] (Default is 2 for Linux): " USER_CHOICE
        if [ "$USER_CHOICE" = "1" ]; then
            MTIP_MODE="workstation"
        else
            MTIP_MODE="server"
        fi
    else
        MTIP_MODE="server"
    fi
fi

if [ -n "$MTIP_MODE" ]; then
    python3 -c "import deployment_config; deployment_config.set_deployment_mode('$MTIP_MODE')" 2>/dev/null
else
    MTIP_MODE="$EXISTING_MODE"
fi

echo "Active Deployment Mode: [$MTIP_MODE]"

# Set host/port defaults based on mode
if [ "$MTIP_MODE" = "server" ]; then
    MTIP_HOST="${MTIP_HOST:-0.0.0.0}"
    MTIP_PORT="${MTIP_PORT:-9999}"
else
    MTIP_HOST="${MTIP_HOST:-127.0.0.1}"
    MTIP_PORT="${MTIP_PORT:-9999}"
fi

echo "Starting backend server (FastAPI) in foreground on $MTIP_HOST:$MTIP_PORT..."
# Using exec for clean signal propagation under process managers (systemd, docker, supervisor)
exec uvicorn main:app --host "$MTIP_HOST" --port "$MTIP_PORT"
