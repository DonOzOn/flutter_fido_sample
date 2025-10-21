#!/bin/bash

echo "🚀 Setting up FIDO2 Demo Project..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}📦 Installing Node.js server dependencies...${NC}"
cd nodejs_server
if npm install; then
    echo -e "${GREEN}✅ Node.js dependencies installed successfully${NC}"
else
    echo -e "${RED}❌ Failed to install Node.js dependencies${NC}"
    exit 1
fi

echo -e "${YELLOW}📱 Installing Flutter dependencies...${NC}"
cd ../flutter_app
if flutter pub get; then
    echo -e "${GREEN}✅ Flutter dependencies installed successfully${NC}"
else
    echo -e "${RED}❌ Failed to install Flutter dependencies${NC}"
    echo -e "${YELLOW}Note: Make sure Flutter is installed and in your PATH${NC}"
fi

cd ..

echo -e "${GREEN}🎉 Setup completed!${NC}"
echo ""
echo -e "${YELLOW}To run the project:${NC}"
echo -e "1. Start the server: ${GREEN}cd nodejs_server && npm start${NC}"
echo -e "2. In another terminal, run Flutter app: ${GREEN}cd flutter_app && flutter run${NC}"
echo ""
echo -e "${YELLOW}Server will be available at: ${GREEN}http://localhost:3000${NC}"
echo -e "${YELLOW}Health check: ${GREEN}http://localhost:3000/health${NC}"
