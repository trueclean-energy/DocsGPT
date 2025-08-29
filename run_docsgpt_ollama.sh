#!/bin/bash

# DocsGPT + Ollama Automated Setup Script
# This script automates the complete setup process for DocsGPT with local Ollama

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/deployment/docker-compose.yaml"
ENV_FILE="$SCRIPT_DIR/.env"

# Default configuration
DEFAULT_MODEL="llama3.2:1b"
DEFAULT_CPU_COMPOSE="$SCRIPT_DIR/deployment/optional/docker-compose.optional.ollama-cpu.yaml"
DEFAULT_GPU_COMPOSE="$SCRIPT_DIR/deployment/optional/docker-compose.optional.ollama-gpu.yaml"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "\n${BOLD}${BLUE}$1${NC}\n"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Docker status
check_docker() {
    print_status "Checking Docker installation..."
    
    if ! command_exists docker; then
        print_error "Docker is not installed. Please install Docker first."
        print_status "Visit: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker Desktop and try again."
        exit 1
    fi
    
    print_success "Docker is running"
}

# Function to check Docker Compose
check_docker_compose() {
    print_status "Checking Docker Compose..."
    
    # Check for docker compose (new version)
    if docker compose version >/dev/null 2>&1; then
        print_success "Docker Compose is available"
        DOCKER_COMPOSE_CMD="docker compose"
        return 0
    fi
    
    # Check for docker-compose (old version)
    if docker-compose --version >/dev/null 2>&1; then
        print_success "Docker Compose is available (legacy)"
        DOCKER_COMPOSE_CMD="docker-compose"
        return 0
    fi
    
    print_error "Docker Compose is not installed"
    print_info "Please install Docker Compose and try again"
    exit 1
}

# Function to check system requirements
check_system_requirements() {
    print_status "Checking system requirements..."
    
    # Check available memory
    local mem_available
    if command_exists free; then
        mem_available=$(free -m | awk 'NR==2{printf "%.0f", $7}')
    elif command_exists vm_stat; then
        # macOS - convert to MB
        mem_available=$(vm_stat | awk '/free/ {gsub(/\./, "", $3); print int($3*4096/1024/1024)}' | head -1)
    else
        print_warning "Could not determine available memory"
        mem_available=0
    fi
    
    if [ "$mem_available" -lt 4000 ]; then
        print_warning "Available memory is less than 4GB. Performance may be limited."
    else
        print_success "System memory: ${mem_available}MB available"
    fi
    
    # Check available disk space
    local disk_available
    disk_available=$(df -m . | awk 'NR==2{print $4}')
    
    if [ "$disk_available" -lt 10240 ]; then
        print_warning "Available disk space is less than 10GB. Consider freeing up space."
    else
        print_success "Disk space: ${disk_available}MB available"
    fi
}

# Function to detect GPU support
detect_gpu() {
    print_status "Detecting GPU support..."
    
    if command_exists nvidia-smi; then
        if nvidia-smi >/dev/null 2>&1; then
            print_success "NVIDIA GPU detected"
            return 0
        fi
    fi
    
    print_status "No NVIDIA GPU detected or drivers not installed"
    return 1
}

# Function to get user preferences
get_user_preferences() {
    print_header "DocsGPT + Ollama Setup"
    
    # Ask for model selection
    echo -e "${BOLD}Available models:${NC}"
    echo "1) llama3.2:1b (1.3GB) - Fast, good for testing"
    echo "2) llama3.2:3b (1.8GB) - Better quality, still fast"
    echo "3) llama3.2:8b (4.7GB) - Good balance of speed and quality"
    echo "4) llama3.2:70b (40GB) - Best quality, requires more resources"
    echo "5) Custom model"
    
    read -p "Choose model (1-5): " model_choice
    
    case $model_choice in
        1) MODEL_NAME="llama3.2:1b" ;;
        2) MODEL_NAME="llama3.2:3b" ;;
        3) MODEL_NAME="llama3.2:8b" ;;
        4) MODEL_NAME="llama3.2:70b" ;;
        5) 
            read -p "Enter custom model name: " MODEL_NAME
            if [ -z "$MODEL_NAME" ]; then
                MODEL_NAME="$DEFAULT_MODEL"
            fi
            ;;
        *) 
            print_warning "Invalid choice, using default model"
            MODEL_NAME="$DEFAULT_MODEL"
            ;;
    esac
    
    # Ask for CPU/GPU preference
    if detect_gpu; then
        echo -e "\n${BOLD}GPU detected! Choose deployment type:${NC}"
        echo "1) CPU (slower but works on all systems)"
        echo "2) GPU (faster, requires NVIDIA Docker runtime)"
        
        read -p "Choose deployment type (1-2): " deployment_choice
        
        case $deployment_choice in
            1) USE_GPU=false ;;
            2) USE_GPU=true ;;
            *) 
                print_warning "Invalid choice, using CPU"
                USE_GPU=false
                ;;
        esac
    else
        print_status "No GPU detected, using CPU deployment"
        USE_GPU=false
    fi
    
    # Ask for port customization
    echo -e "\n${BOLD}Port configuration:${NC}"
    echo "Default ports:"
    echo "- Frontend: 5173"
    echo "- Backend API: 7091"
    echo "- Ollama API: 11434"
    
    read -p "Use default ports? (y/n): " use_default_ports
    
    if [[ $use_default_ports =~ ^[Nn]$ ]]; then
        read -p "Frontend port (default 5173): " FRONTEND_PORT
        read -p "Backend port (default 7091): " BACKEND_PORT
        read -p "Ollama port (default 11434): " OLLAMA_PORT
        
        FRONTEND_PORT=${FRONTEND_PORT:-5173}
        BACKEND_PORT=${BACKEND_PORT:-7091}
        OLLAMA_PORT=${OLLAMA_PORT:-11434}
    else
        FRONTEND_PORT=5173
        BACKEND_PORT=7091
        OLLAMA_PORT=11434
    fi
}

# Function to create environment file
create_env_file() {
    print_status "Creating environment configuration..."
    
    # Create .env file in root directory
    cat > "$ENV_FILE" << EOF
# DocsGPT Configuration
API_KEY=xxxx
LLM_PROVIDER=openai
LLM_NAME=$MODEL_NAME
VITE_API_STREAMING=true
OPENAI_BASE_URL=http://ollama:11434/v1
EMBEDDINGS_NAME=huggingface_sentence-transformers/all-mpnet-base-v2

# Custom ports (if specified)
FRONTEND_PORT=$FRONTEND_PORT
BACKEND_PORT=$BACKEND_PORT
OLLAMA_PORT=$OLLAMA_PORT
EOF
    
    # Also create .env file in deployment directory for docker-compose
    cat > "$SCRIPT_DIR/deployment/.env" << EOF
# DocsGPT Configuration
API_KEY=xxxx
LLM_PROVIDER=openai
LLM_NAME=$MODEL_NAME
VITE_API_STREAMING=true
OPENAI_BASE_URL=http://ollama:11434/v1
EMBEDDINGS_NAME=huggingface_sentence-transformers/all-mpnet-base-v2
EOF
    
    print_success "Environment file created: $ENV_FILE"
    print_success "Environment file also created in deployment directory"
}

# Function to create custom docker-compose file with custom ports
create_custom_compose() {
    if [ "$FRONTEND_PORT" != "5173" ] || [ "$BACKEND_PORT" != "7091" ] || [ "$OLLAMA_PORT" != "11434" ]; then
        print_status "Creating custom docker-compose file with custom ports..."
        
        # Create custom compose file
        cat > "$SCRIPT_DIR/deployment/docker-compose.custom.yaml" << EOF
version: "3.8"
services:
  frontend:
    ports:
      - "$FRONTEND_PORT:5173"
  
  backend:
    ports:
      - "$BACKEND_PORT:7091"
  
  ollama:
    ports:
      - "$OLLAMA_PORT:11434"
EOF
        
        CUSTOM_COMPOSE="-f $SCRIPT_DIR/deployment/docker-compose.custom.yaml"
        print_success "Custom compose file created with ports: $FRONTEND_PORT, $BACKEND_PORT, $OLLAMA_PORT"
    else
        CUSTOM_COMPOSE=""
    fi
}

# Function to start services
start_services() {
    print_status "Starting DocsGPT services..."
    
    # Determine which compose files to use
    local compose_files=("-f" "$COMPOSE_FILE")
    
    if [ "$USE_GPU" = true ]; then
        compose_files+=("-f" "$DEFAULT_GPU_COMPOSE")
        print_status "Using GPU configuration"
    else
        compose_files+=("-f" "$DEFAULT_CPU_COMPOSE")
        print_status "Using CPU configuration"
    fi
    
    if [ -n "$CUSTOM_COMPOSE" ]; then
        compose_files+=("-f" "$SCRIPT_DIR/deployment/docker-compose.custom.yaml")
    fi
    
    # Build and start services
    print_status "Building Docker images..."
    $DOCKER_COMPOSE_CMD "${compose_files[@]}" build
    
    print_status "Starting services..."
    $DOCKER_COMPOSE_CMD "${compose_files[@]}" up -d
    
    print_success "Services started successfully"
}

# Function to wait for services to be ready
wait_for_services() {
    print_status "Waiting for services to be ready..."
    
    # Determine which compose files to use
    local compose_files=("-f" "$COMPOSE_FILE")
    
    if [ "$USE_GPU" = true ]; then
        compose_files+=("-f" "$DEFAULT_GPU_COMPOSE")
    else
        compose_files+=("-f" "$DEFAULT_CPU_COMPOSE")
    fi
    
    if [ -n "$CUSTOM_COMPOSE" ]; then
        compose_files+=("-f" "$SCRIPT_DIR/deployment/docker-compose.custom.yaml")
    fi
    
    # Wait for Ollama to be ready
    local attempts=0
    while [ $attempts -lt 60 ]; do
        if $DOCKER_COMPOSE_CMD "${compose_files[@]}" ps | grep -q "ollama.*Up"; then
            print_success "Ollama service is ready"
            break
        fi
        sleep 5
        attempts=$((attempts + 1))
        print_status "Waiting for Ollama... (attempt $attempts/60)"
    done
    
    if [ $attempts -eq 60 ]; then
        print_error "Ollama service failed to start"
        docker compose "${compose_files[@]}" logs ollama
        exit 1
    fi
    
    # Wait for backend to be ready
    attempts=0
    while [ $attempts -lt 60 ]; do
        if curl -s http://localhost:$BACKEND_PORT/health >/dev/null 2>&1; then
            print_success "Backend service is ready"
            break
        fi
        sleep 5
        attempts=$((attempts + 1))
        print_status "Waiting for backend... (attempt $attempts/60)"
    done
    
    if [ $attempts -eq 60 ]; then
        print_warning "Backend service may not be fully ready"
    fi
}

# Function to pull model
pull_model() {
    print_status "Pulling Ollama model: $MODEL_NAME"
    
    # Determine which compose files to use
    local compose_files=("-f" "$COMPOSE_FILE")
    
    if [ "$USE_GPU" = true ]; then
        compose_files+=("-f" "$DEFAULT_GPU_COMPOSE")
    else
        compose_files+=("-f" "$DEFAULT_CPU_COMPOSE")
    fi
    
    if [ -n "$CUSTOM_COMPOSE" ]; then
        compose_files+=("-f" "$SCRIPT_DIR/deployment/docker-compose.custom.yaml")
    fi
    
    # Check if model is already available
    if docker compose "${compose_files[@]}" exec -T ollama ollama list | grep -q "$MODEL_NAME"; then
        print_success "Model $MODEL_NAME is already available"
        return 0
    fi
    
    # Pull the model
    print_status "Downloading model (this may take several minutes)..."
    docker compose "${compose_files[@]}" exec -T ollama ollama pull "$MODEL_NAME"
    
    if [ $? -eq 0 ]; then
        print_success "Model $MODEL_NAME downloaded successfully"
    else
        print_error "Failed to download model $MODEL_NAME"
        exit 1
    fi
}

# Function to display final status
show_final_status() {
    print_header "Setup Complete! 🎉"
    
    echo -e "${BOLD}DocsGPT is now running with the following configuration:${NC}"
    echo -e "• Model: ${GREEN}$MODEL_NAME${NC}"
    echo -e "• Deployment: ${GREEN}$([ "$USE_GPU" = true ] && echo "GPU" || echo "CPU")${NC}"
    echo -e "• Frontend: ${GREEN}http://localhost:$FRONTEND_PORT${NC}"
    echo -e "• Backend API: ${GREEN}http://localhost:$BACKEND_PORT${NC}"
    echo -e "• Ollama API: ${GREEN}http://localhost:$OLLAMA_PORT${NC}"
    
    echo -e "\n${BOLD}Next steps:${NC}"
    echo "1. Open your browser and go to: http://localhost:$FRONTEND_PORT"
    echo "2. Upload your documents in the DocsGPT interface"
    echo "3. Start chatting with your documents!"
    
    echo -e "\n${BOLD}Useful commands:${NC}"
    echo "• Check service status: docker compose ps"
    echo "• View logs: docker compose logs"
    echo "• Stop services: docker compose down"
    echo "• Restart services: docker compose restart"
    
    echo -e "\n${BOLD}Model management:${NC}"
    echo "• List models: docker compose exec ollama ollama list"
    echo "• Pull new model: docker compose exec ollama ollama pull <model_name>"
    echo "• Change model: Edit LLM_NAME in .env file and restart backend"
    
    print_success "DocsGPT is ready to use!"
    echo -e "\n${BOLD}File Upload Limits:${NC}"
    echo "• Maximum file size: 100MB per file"
    echo "• Multiple files can be uploaded together"
    echo "• Supported formats: PDF, DOCX, TXT, XLSX, CSV, and more"
}

# Function to handle cleanup on script exit
cleanup() {
    if [ $? -ne 0 ]; then
        print_error "Setup failed. Check the logs above for details."
        print_status "You can try running the script again or check the troubleshooting guide."
    fi
}

# Main execution
main() {
    # Set up cleanup trap
    trap cleanup EXIT
    
    # Check if we're in the right directory
    if [ ! -f "$COMPOSE_FILE" ]; then
        print_error "Please run this script from the DocsGPT root directory"
        exit 1
    fi
    
    # Run setup steps
    check_docker
    check_docker_compose
    check_system_requirements
    get_user_preferences
    create_env_file
    create_custom_compose
    start_services
    wait_for_services
    pull_model
    show_final_status
    
    # Remove cleanup trap on success
    trap - EXIT
}

# Run main function
main "$@"
