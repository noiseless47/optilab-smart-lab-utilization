#!/bin/bash

################################################################################
# OptiLab Queue Setup Script
# Purpose: Initialize RabbitMQ queues and exchanges for the OptiLab system
# Usage: ./queue_setup.sh [rabbitmq|redis]
################################################################################

set -e

# Configuration
QUEUE_TYPE="${1:-rabbitmq}"
RABBITMQ_HOST="${RABBITMQ_HOST:-localhost}"
RABBITMQ_PORT="${RABBITMQ_PORT:-15672}"
RABBITMQ_USER="${RABBITMQ_USER:-guest}"
RABBITMQ_PASS="${RABBITMQ_PASS:-guest}"

REDIS_HOST="${REDIS_HOST:-localhost}"
REDIS_PORT="${REDIS_PORT:-6379}"

# Queue names
DISCOVERY_QUEUE="discovery_queue"
METRICS_QUEUE="metrics_queue"
ALERT_QUEUE="alert_queue"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

################################################################################
# RabbitMQ Setup
################################################################################

setup_rabbitmq() {
    log_info "Setting up RabbitMQ queues..."
    
    # Check if RabbitMQ is running
    if ! curl -s -u "$RABBITMQ_USER:$RABBITMQ_PASS" \
         "http://$RABBITMQ_HOST:$RABBITMQ_PORT/api/overview" > /dev/null 2>&1; then
        log_error "RabbitMQ not accessible at http://$RABBITMQ_HOST:$RABBITMQ_PORT"
        log_info "Start RabbitMQ with: docker run -d --name rabbitmq -p 5672:5672 -p 15672:15672 rabbitmq:3-management"
        exit 1
    fi
    
    log_success "RabbitMQ is accessible"
    
    # Create vhost (using default '/')
    VHOST="%2F"  # URL-encoded '/'
    
    # Declare queues
    declare_queue "$DISCOVERY_QUEUE" "Queue for discovered systems"
    declare_queue "$METRICS_QUEUE" "Queue for collected metrics"
    declare_queue "$ALERT_QUEUE" "Queue for system alerts"
    
    # Create exchange (optional, for advanced routing)
    create_exchange "optilab_exchange" "topic"
    
    # Bind queues to exchange
    bind_queue "$DISCOVERY_QUEUE" "optilab_exchange" "discovery.#"
    bind_queue "$METRICS_QUEUE" "optilab_exchange" "metrics.#"
    bind_queue "$ALERT_QUEUE" "optilab_exchange" "alerts.#"
    
    log_success "RabbitMQ setup complete!"
    log_info "Management UI: http://$RABBITMQ_HOST:$RABBITMQ_PORT"
    log_info "Login: $RABBITMQ_USER / $RABBITMQ_PASS"
}

declare_queue() {
    local queue_name="$1"
    local description="$2"
    
    log_info "Creating queue: $queue_name"
    
    local result=$(curl -s -u "$RABBITMQ_USER:$RABBITMQ_PASS" \
         -H "Content-Type: application/json" \
         -X PUT \
         -d "{\"durable\":true,\"auto_delete\":false,\"arguments\":{}}" \
         "http://$RABBITMQ_HOST:$RABBITMQ_PORT/api/queues/$VHOST/$queue_name")
    
    if [[ $? -eq 0 ]]; then
        log_success "  └─ $queue_name created"
    else
        log_error "  └─ Failed to create $queue_name"
    fi
}

create_exchange() {
    local exchange_name="$1"
    local exchange_type="$2"
    
    log_info "Creating exchange: $exchange_name (type: $exchange_type)"
    
    curl -s -u "$RABBITMQ_USER:$RABBITMQ_PASS" \
         -H "Content-Type: application/json" \
         -X PUT \
         -d "{\"type\":\"$exchange_type\",\"durable\":true,\"auto_delete\":false}" \
         "http://$RABBITMQ_HOST:$RABBITMQ_PORT/api/exchanges/$VHOST/$exchange_name" > /dev/null
    
    log_success "  └─ $exchange_name created"
}

bind_queue() {
    local queue_name="$1"
    local exchange_name="$2"
    local routing_key="$3"
    
    log_info "Binding $queue_name to $exchange_name with key: $routing_key"
    
    curl -s -u "$RABBITMQ_USER:$RABBITMQ_PASS" \
         -H "Content-Type: application/json" \
         -X POST \
         -d "{\"routing_key\":\"$routing_key\"}" \
         "http://$RABBITMQ_HOST:$RABBITMQ_PORT/api/bindings/$VHOST/e/$exchange_name/q/$queue_name" > /dev/null
    
    log_success "  └─ Binding created"
}

################################################################################
# Redis Setup
################################################################################

setup_redis() {
    log_info "Setting up Redis queues..."
    
    # Check if Redis is running
    if ! redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" ping > /dev/null 2>&1; then
        log_error "Redis not accessible at $REDIS_HOST:$REDIS_PORT"
        log_info "Start Redis with: docker run -d --name redis -p 6379:6379 redis:latest"
        exit 1
    fi
    
    log_success "Redis is accessible"
    
    # Initialize queues (Redis lists)
    log_info "Initializing Redis lists (queues)..."
    
    # Clear existing queues (optional, comment out in production)
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" DEL "$DISCOVERY_QUEUE" > /dev/null
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" DEL "$METRICS_QUEUE" > /dev/null
    redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" DEL "$ALERT_QUEUE" > /dev/null
    
    log_success "Redis queues ready:"
    log_info "  - $DISCOVERY_QUEUE"
    log_info "  - $METRICS_QUEUE"
    log_info "  - $ALERT_QUEUE"
    
    log_success "Redis setup complete!"
}

################################################################################
# Docker Compose Setup
################################################################################

generate_docker_compose() {
    log_info "Generating docker-compose.yml for queue services..."
    
    cat > docker-compose.queue.yml << 'EOF'
version: '3.8'

services:
  rabbitmq:
    image: rabbitmq:3-management
    container_name: optilab-rabbitmq
    ports:
      - "5672:5672"   # AMQP protocol
      - "15672:15672" # Management UI
    environment:
      RABBITMQ_DEFAULT_USER: guest
      RABBITMQ_DEFAULT_PASS: guest
    volumes:
      - rabbitmq_data:/var/lib/rabbitmq
    networks:
      - optilab_network
    restart: unless-stopped

  redis:
    image: redis:latest
    container_name: optilab-redis
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    networks:
      - optilab_network
    restart: unless-stopped
    command: redis-server --appendonly yes

volumes:
  rabbitmq_data:
  redis_data:

networks:
  optilab_network:
    driver: bridge
EOF
    
    log_success "Created docker-compose.queue.yml"
    log_info "Start services with: docker-compose -f docker-compose.queue.yml up -d"
}

################################################################################
# Main
################################################################################

main() {
    echo "=== OptiLab Queue Setup ==="
    echo
    
    case "$QUEUE_TYPE" in
        rabbitmq)
            setup_rabbitmq
            ;;
        redis)
            setup_redis
            ;;
        docker)
            generate_docker_compose
            ;;
        *)
            log_error "Unknown queue type: $QUEUE_TYPE"
            echo "Usage: $0 [rabbitmq|redis|docker]"
            exit 1
            ;;
    esac
    
    echo
    log_success "=== Setup Complete ==="
    echo
    log_info "Next steps:"
    log_info "1. Start queue consumer: python3 collector/queue_consumer.py metrics"
    log_info "2. Enable queue in scanner: QUEUE_ENABLED=true ./collector/scanner.sh ..."
    log_info "3. Enable queue in collector: ./collector/ssh_script.sh --all --queue-enabled"
}

main
