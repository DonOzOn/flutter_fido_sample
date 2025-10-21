#!/bin/bash

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

echo "🚀 Starting FIDO2 Server..."
echo "📂 Working directory: $SCRIPT_DIR"

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies first..."
    npm install
fi

# Start the server
echo "🖥️  Starting server on port 3000..."
npm start
