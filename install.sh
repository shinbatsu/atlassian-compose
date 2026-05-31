#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"


confirm() {
    local prompt="$1"
    local default="${2:-y}"
    local yn
    
    while true; do
        if [ "$default" = "y" ]; then
            read -r -p "$prompt [Y/n]: " yn
        else
            read -r -p "$prompt [y/N]: " yn
        fi
        
        yn=${yn:-$default}
        
        case "$yn" in
            [Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
            *)
                echo "  Please enter 'y' or 'n'."
                ;;
        esac
    done
}

prompt_value() {
    local prompt="$1"
    local default="$2"
    local value
    
    if [ -n "$default" ]; then
        read -r -p "$prompt [$default]: " value
        value=${value:-$default}
    else
        read -r -p "$prompt: " value
    fi
    
    echo "$value"
}

prompt_password() {
    local prompt="$1"
    local default="$2"
    local value
    
    if [ -n "$default" ]; then
        read -r -p "$prompt (leave empty for auto-generation): " value
        value=${value:-$default}
    else
        read -r -p "$prompt: " value
    fi
    
    echo "$value"
}


check_deps() {
    if ! command -v docker &> /dev/null; then
        echo "Error: Docker not found!"
        echo "Install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi

    COMPOSE_CMD=""
    if docker compose version &> /dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        echo "Error: Docker Compose not found!"
        exit 1
    fi
}


generate_password() {
    echo "$(openssl rand -base64 32 2>/dev/null || head -c 32 /dev/urandom | base64 2>/dev/null || date +%s | sha256sum | base64 | head -c 32)"
}


select_components() {

    INSTALL_JIRA=true
    INSTALL_CONFLUENCE=true
    INSTALL_CROWD=false
    INSTALL_BITBUCKET=false
    
    echo "======================================================================"
    echo "  Atlassian Ecosystem Installer"
    echo "======================================================================"
    echo ""
    echo "  ✓ Jira Software       — mandatory component"
    echo "  ✓ Confluence          — mandatory component"
    echo ""
    echo "Additional services (optional):"
    echo ""

    echo "  ┌─ Crowd ──────────────────────────────────────────────────────────┐"
    echo "  │  Centralized user management and single sign-on (SSO).          │"
    echo "  │  Allows synchronizing users between Atlassian products          │"
    echo "  │  and provides LDAP-like authentication.                         │"
    echo "  └──────────────────────────────────────────────────────────────────┘"
    if confirm "Install Crowd?"; then
        INSTALL_CROWD=true
    fi
    echo ""

    echo "  ┌─ Bitbucket ──────────────────────────────────────────────────────┐"
    echo "  │  Git repository for team development. Supports pull              │"
    echo "  │  requests, code review, CI/CD integration via Pipelines.         │"
    echo "  │  High performance even on large monorepos.                       │"
    echo "  └──────────────────────────────────────────────────────────────────┘"
    if confirm "Install Bitbucket?"; then
        INSTALL_BITBUCKET=true
    fi
    echo ""

    echo "Selected components for installation:"
    echo "  ✓ Jira Software       (mandatory)"
    echo "  ✓ Confluence          (mandatory)"
    $INSTALL_CROWD     && echo "  ✓ Crowd"               || echo "  ✗ Crowd"
    $INSTALL_BITBUCKET && echo "  ✓ Bitbucket"           || echo "  ✗ Bitbucket"
    echo ""
}


configure_databases() {
    local db_user db_password db_prefix

    echo "--- Database configuration ---"

    db_user=$(prompt_value "Common user for all databases" "atlassian")
    
    local generated_pass
    generated_pass=$(generate_password)
    db_password=$(prompt_password "Common password for all databases" "$generated_pass")

    db_prefix=$(prompt_value "Prefix for database names (e.g., 'atlassian' → atlassian_jiradb)" "atlassian")

    {

        echo "JIRA_DB_HOST=jira_db"
        echo "JIRA_DB_NAME=${db_prefix}_jiradb"
        echo "JIRA_DB_USER=$db_user"
        echo "JIRA_DB_PASSWORD=$db_password"

        echo "CONFLUENCE_DB_HOST=confluence_db"
        echo "CONFLUENCE_DB_NAME=${db_prefix}_confluencedb"
        echo "CONFLUENCE_DB_USER=$db_user"
        echo "CONFLUENCE_DB_PASSWORD=$db_password"

        $INSTALL_CROWD     && echo "CROWD_DB_HOST=crowd_db"     && echo "CROWD_DB_NAME=${db_prefix}_crowddb"     && echo "CROWD_DB_USER=$db_user"     && echo "CROWD_DB_PASSWORD=$db_password"
        $INSTALL_BITBUCKET && echo "BITBUCKET_DB_HOST=bitbucket_db" && echo "BITBUCKET_DB_NAME=${db_prefix}_bitbucketdb" && echo "BITBUCKET_DB_USER=$db_user" && echo "BITBUCKET_DB_PASSWORD=$db_password"
    } >> "$ENV_FILE"
}



configure_certificates() {
    echo ""
    echo "--- Certificate configuration ---"
    
    if confirm "Generate self-signed OpenSSL certificates?" "y"; then
        echo "USE_CUSTOM_CERTS=true" >> "$ENV_FILE"
        echo "Certificates will be generated in ./certs/"
        echo "For production, replace them with trusted ones."
    else
        echo "USE_CUSTOM_CERTS=false" >> "$ENV_FILE"
    fi
}


configure_proxy() {
    echo ""
    echo "--- Reverse Proxy configuration ---"

    if confirm "Use Traefik reverse proxy? (single entry point via domains)" "y"; then

        echo "USE_TRAEFIK=true" >> "$ENV_FILE"

        echo "JIRA_PROXY_NAME=$(prompt_value "Domain for Jira" "jira.local")" >> "$ENV_FILE"
        echo "CONFLUENCE_PROXY_NAME=$(prompt_value "Domain for Confluence" "confluence.local")" >> "$ENV_FILE"

        if $INSTALL_CROWD; then
            echo "CROWD_PROXY_NAME=$(prompt_value "Domain for Crowd" "crowd.local")" >> "$ENV_FILE"
        fi

        if $INSTALL_BITBUCKET; then
            echo "BITBUCKET_PROXY_NAME=$(prompt_value "Domain for Bitbucket" "bitbucket.local")" >> "$ENV_FILE"
        fi
    else
        echo "USE_TRAEFIK=false" >> "$ENV_FILE"
    fi
}


configure_corporate_proxy() {
    echo ""
    echo "--- Corporate proxy configuration ---"

    if confirm "Do you use a corporate HTTP proxy?" "n"; then

        local http_proxy https_proxy no_proxy
        local http_host http_port

        http_proxy=$(prompt_value "HTTP Proxy URL" "http://proxy.company.com:8080")

        https_proxy=$(prompt_value "HTTPS Proxy URL" "http://proxy.company.com:8080")

        no_proxy=$(prompt_value "Exceptions (comma-separated)" "localhost,127.0.0.1,.local,traefik,jira,crowd,confluence,bitbucket")

        {
            echo "HTTP_PROXY=$http_proxy"
            echo "HTTPS_PROXY=$https_proxy"
            echo "NO_PROXY=$no_proxy"
            echo ""

            http_host=$(echo "$http_proxy" | sed -E 's|https?://||' | cut -d: -f1)
            http_port=$(echo "$http_proxy" | sed -E 's|https?://||' | cut -d: -f2)
            echo "JAVA_PROXY_OPTS=-Dhttp.proxyHost=$http_host -Dhttp.proxyPort=$http_port -Dhttps.proxyHost=$http_host -Dhttps.proxyPort=$http_port -Dhttp.nonProxyHosts=localhost|127.0.0.1|*.local"
        } >> "$ENV_FILE"
    fi
}


generate_env_file() {

    cat > "$ENV_FILE" << 'EOF'

POSTGRES_TAG=16-alpine
JIRA_VERSION=10.7.3
CROWD_VERSION=7.2-ubuntu-jdk-21
CONFLUENCE_VERSION=10.2.3-ubi9-jdk21
BITBUCKET_VERSION=9.6.2-ubi9-jdk21

AGENT_JAR_PATH=./agent/handler.jar

COMPOSE_PROJECT_NAME=atlassian

EOF

    echo "# ========== DATABASES ==========" >> "$ENV_FILE"
    configure_databases

    local tz
    tz=$(prompt_value "Timezone" "Europe/Moscow")
    {
        echo ""
        echo "# ========== GENERAL =========="
        echo "TIMEZONE=$tz"
    } >> "$ENV_FILE"

    {
        echo ""
        echo "# ========== CERTIFICATES =========="
    } >> "$ENV_FILE"
    configure_certificates

    {
        echo ""
        echo "# ========== REVERSE PROXY =========="
    } >> "$ENV_FILE"
    configure_proxy

    {
        echo ""
        echo "# ========== CORPORATE PROXY =========="
    } >> "$ENV_FILE"
    configure_corporate_proxy
}


show_summary() {
    echo ""
    echo "======================================================================"
    echo "  Configuration completed"
    echo "======================================================================"
    echo ""
    echo "Components:"
    echo "  ✓ Jira Software       (mandatory)"
    echo "  ✓ Confluence          (mandatory)"
    $INSTALL_CROWD     && echo "  ✓ Crowd"               || echo "  ✗ Crowd"
    $INSTALL_BITBUCKET && echo "  ✓ Bitbucket"           || echo "  ✗ Bitbucket"
    echo ""
    echo ".env file: $ENV_FILE"
    echo ""

    if grep -q "USE_CUSTOM_CERTS=true" "$ENV_FILE" 2>/dev/null; then
        if [ -x "$SCRIPT_DIR/certs/generate-certs.sh" ]; then

            DOMAINS=()
            while IFS='=' read -r _ val; do
                DOMAINS+=("$val")
            done < <(grep -E '^(JIRA|CROWD|CONFLUENCE|BITBUCKET)_PROXY_NAME' "$ENV_FILE" 2>/dev/null || true)
            DOMAINS+=("traefik.local")
            if [ ${#DOMAINS[@]} -gt 0 ]; then
                bash "$SCRIPT_DIR/certs/generate-certs.sh" "${DOMAINS[@]}" || true
            fi
        fi
    fi

    if confirm "Start containers now?" "y"; then
        cd "$SCRIPT_DIR"

        if grep -q "USE_TRAEFIK=true" "$ENV_FILE" 2>/dev/null; then
            $COMPOSE_CMD --profile with-proxy up -d
        else
            $COMPOSE_CMD up -d
        fi

        local running=""
        running+="Containers started!"
        running+=$'\n'

        domain=$(grep JIRA_PROXY_NAME "$ENV_FILE" 2>/dev/null | cut -d= -f2)
        domain=${domain:-jira.local}
        running+="  Jira:        http://localhost:8080  (https://$domain)"
        running+=$'\n'

        domain=$(grep CONFLUENCE_PROXY_NAME "$ENV_FILE" 2>/dev/null | cut -d= -f2)
        domain=${domain:-confluence.local}
        running+="  Confluence:  http://localhost:8090  (https://$domain)"
        running+=$'\n'

        if $INSTALL_CROWD; then
            domain=$(grep CROWD_PROXY_NAME "$ENV_FILE" 2>/dev/null | cut -d= -f2)
            domain=${domain:-crowd.local}
            running+="  Crowd:       http://localhost:8095  (https://$domain)"
            running+=$'\n'
        fi
        if $INSTALL_BITBUCKET; then
            domain=$(grep BITBUCKET_PROXY_NAME "$ENV_FILE" 2>/dev/null | cut -d= -f2)
            domain=${domain:-bitbucket.local}
            running+="  Bitbucket:   http://localhost:7990  (https://$domain)"
            running+=$'\n'
        fi

        running+=$'\n'
        running+="  Traefik Dashboard: http://localhost:8081"
        running+=$'\n'
        running+=$'\n'
        running+="For logs: $COMPOSE_CMD logs -f"
        running+=$'\n'
        running+="To stop: $COMPOSE_CMD down"

        echo ""
        echo "$running"
    else
        echo ""
        echo "To start manually:"
        echo "  cd $SCRIPT_DIR && $COMPOSE_CMD up -d"
    fi
}


cd "$SCRIPT_DIR"

check_deps
select_components
generate_env_file
show_summary

exit 0