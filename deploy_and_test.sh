#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
AWS_IP="18.217.65.246"
AWS_KEY=".aws/aws-docgpt-key.pem"
AWS_USER="ubuntu"
REPO_DIR="/Users/alvin/personal/DocsGPT"

echo -e "${BLUE}🚀 DocsGPT Auto Deploy and Test Script${NC}"
echo "=================================="

# Function to print status
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Step 1: Check if we're in the right directory
print_status "Checking current directory..."
if [ ! -f "run_docsgpt_ollama.sh" ]; then
    print_error "Not in DocsGPT directory. Please run this script from the DocsGPT root directory."
    exit 1
fi
print_success "In correct directory"

# Step 2: Check git status
print_status "Checking git status..."
if [ -n "$(git status --porcelain)" ]; then
    print_status "Changes detected, committing..."
    git add .
    git commit -m "Auto-deploy: $(date '+%Y-%m-%d %H:%M:%S')"
    print_success "Changes committed"
else
    print_status "No changes to commit"
fi

# Step 3: Push to remote
print_status "Pushing to remote repository..."
if git push; then
    print_success "Pushed to remote repository"
else
    print_error "Failed to push to remote repository"
    exit 1
fi

# Step 4: Check if AWS key exists
print_status "Checking AWS key..."
if [ ! -f "$AWS_KEY" ]; then
    print_error "AWS key not found at $AWS_KEY"
    exit 1
fi
print_success "AWS key found"

# Step 5: Update AWS instance
print_status "Updating AWS instance..."
ssh -i "$AWS_KEY" -o StrictHostKeyChecking=no "$AWS_USER@$AWS_IP" << 'EOF'
    cd ~/DocsGPT
    echo "Pulling latest changes..."
    git pull
    echo "Stopping current services..."
    sudo docker-compose -f deployment/docker-compose.yaml down
    echo "Starting services with latest changes..."
    sudo docker-compose -f deployment/docker-compose.yaml up -d
    echo "Waiting for services to start..."
    sleep 10
    echo "Checking service status..."
    sudo docker-compose -f deployment/docker-compose.yaml ps
EOF

if [ $? -eq 0 ]; then
    print_success "AWS instance updated"
else
    print_error "Failed to update AWS instance"
    exit 1
fi

# Step 6: Test the deployment
print_status "Testing deployment..."

# Wait a bit for services to fully start
sleep 15

# Test frontend
print_status "Testing frontend..."
if curl -s -f "http://$AWS_IP:5173" > /dev/null; then
    print_success "Frontend is accessible at http://$AWS_IP:5173"
else
    print_warning "Frontend not accessible yet, may still be starting"
fi

# Test backend
print_status "Testing backend..."
if curl -s -f "http://$AWS_IP:7091/health" > /dev/null; then
    print_success "Backend is accessible at http://$AWS_IP:7091"
else
    print_warning "Backend not accessible yet, may still be starting"
fi

# Test Ollama
print_status "Testing Ollama..."
if curl -s -f "http://$AWS_IP:11434/api/tags" > /dev/null; then
    print_success "Ollama is accessible at http://$AWS_IP:11434"
else
    print_warning "Ollama not accessible yet, may still be starting"
fi

# Step 7: Check service logs
print_status "Checking service logs..."
ssh -i "$AWS_KEY" -o StrictHostKeyChecking=no "$AWS_USER@$AWS_IP" << 'EOF'
    echo "=== Docker Compose Status ==="
    sudo docker-compose -f deployment/docker-compose.yaml ps
    echo ""
    echo "=== Recent Logs ==="
    sudo docker-compose -f deployment/docker-compose.yaml logs --tail=20
EOF

# Step 8: Final status
echo ""
echo -e "${GREEN}🎉 Deployment Complete!${NC}"
echo "=================================="
echo -e "${BLUE}Frontend:${NC} http://$AWS_IP:5173"
echo -e "${BLUE}Backend:${NC} http://$AWS_IP:7091"
echo -e "${BLUE}Ollama:${NC} http://$AWS_IP:11434"
echo ""
echo -e "${YELLOW}If services are not accessible, they may still be starting up.${NC}"
echo -e "${YELLOW}Check the logs above for any errors.${NC}"
