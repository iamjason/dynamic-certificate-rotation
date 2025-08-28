#!/bin/bash

# Restart mTLS Demo Server Script
# Stops any running server and starts a fresh instance

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "🔄 Restarting mTLS Demo Server"
echo "=============================="

# Stop any running server processes
echo "🛑 Stopping existing server processes..."
pkill -f "node server.js" || true
pkill -f "start-server.sh" || true

# Wait a moment for processes to terminate
sleep 2

# Check if port 8443 is still in use
if lsof -ti:8443 > /dev/null 2>&1; then
    echo "⚠️  Port 8443 still in use, force killing processes..."
    lsof -ti:8443 | xargs kill -9 || true
    sleep 1
fi

# Start the server
echo "🚀 Starting mTLS Demo Server..."
cd "$PROJECT_ROOT"
exec ./scripts/start-server.sh