#!/bin/bash

# Stop mTLS Demo Server Script
# Gracefully stops the running server

set -e

echo "🛑 Stopping mTLS Demo Server"
echo "============================"

# Stop server processes
echo "🔍 Looking for server processes..."

# Find and stop Node.js server
SERVER_PIDS=$(pgrep -f "node server.js" 2>/dev/null || true)
if [ ! -z "$SERVER_PIDS" ]; then
    echo "📋 Found Node.js server processes: $SERVER_PIDS"
    echo "$SERVER_PIDS" | xargs kill -TERM
    echo "✅ Sent SIGTERM to Node.js server"
else
    echo "ℹ️  No Node.js server processes found"
fi

# Find and stop start-server script
SCRIPT_PIDS=$(pgrep -f "start-server.sh" 2>/dev/null || true)
if [ ! -z "$SCRIPT_PIDS" ]; then
    echo "📋 Found start-server script processes: $SCRIPT_PIDS"
    echo "$SCRIPT_PIDS" | xargs kill -TERM
    echo "✅ Sent SIGTERM to start-server script"
else
    echo "ℹ️  No start-server script processes found"
fi

# Wait for graceful shutdown
echo "⏳ Waiting for processes to terminate..."
sleep 3

# Check if any processes are still running and force kill if needed
REMAINING_SERVER=$(pgrep -f "node server.js" 2>/dev/null || true)
REMAINING_SCRIPT=$(pgrep -f "start-server.sh" 2>/dev/null || true)

if [ ! -z "$REMAINING_SERVER" ]; then
    echo "⚠️  Force killing remaining Node.js server processes..."
    echo "$REMAINING_SERVER" | xargs kill -9
fi

if [ ! -z "$REMAINING_SCRIPT" ]; then
    echo "⚠️  Force killing remaining start-server script processes..."
    echo "$REMAINING_SCRIPT" | xargs kill -9
fi

# Check port status
if lsof -ti:8443 > /dev/null 2>&1; then
    echo "⚠️  Port 8443 still in use, force killing..."
    lsof -ti:8443 | xargs kill -9 2>/dev/null || true
    sleep 1
fi

# Final check
if lsof -ti:8443 > /dev/null 2>&1; then
    echo "❌ Port 8443 is still in use"
    echo "🔍 Processes using port 8443:"
    lsof -i:8443
    exit 1
else
    echo "✅ Server stopped successfully"
    echo "🌐 Port 8443 is now free"
fi