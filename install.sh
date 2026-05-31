#!/bin/bash
# ============================================================================
# Atlassian Ecosystem Installer (simple edition)
# Интерактивный скрипт для настройки и деплоя Atlassian продуктов
# Jira и Confluence устанавливаются всегда (обязательные).
# Crowd и Bitbucket — опционально.
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
COMPOSE_FILE="$SCRIPT_DIR/docker-compose.yml"

# ============================================================================
# Helper functions
# ============================================================================

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
                echo "  Пожалуйста, введите 'y' или 'n'."
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
        read -r -p "$prompt (оставьте пустым для автогенерации): " value
        value=${value:-$default}
    else
        read -r -p "$prompt: " value
    fi
    
    echo "$value"
}

# ============================================================================
# Dependency Check
# ============================================================================

check_deps() {
    if ! command -v docker &> /dev/null; then
        echo "Ошибка: Docker не найден!"
        echo "Установите Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi

    COMPOSE_CMD=""
    if docker compose version &> /dev/null 2>&1; then
        COMPOSE_CMD="docker compose"
    elif command -v docker-compose &> /dev/null; then
        COMPOSE_CMD="docker-compose"
    else
        echo "Ошибка: Docker Compose не найден!"
        exit 1
    fi
}

# ============================================================================
# Generate random password
# ============================================================================

generate_password() {
    echo "$(openssl rand -base64 32 2>/dev/null || head -c 32 /dev/urandom | base64 2>/dev/null || date +%s | sha256sum | base64 | head -c 32)"
}

# ============================================================================
# Component Selection
# ============================================================================

select_components() {
    # Jira и Confluence — всегда обязательные
    INSTALL_JIRA=true
    INSTALL_CONFLUENCE=true
    INSTALL_CROWD=false
    INSTALL_BITBUCKET=false
    
    echo "======================================================================"
    echo "  Atlassian Ecosystem Installer"
    echo "======================================================================"
    echo ""
    echo "  ✓ Jira Software       — обязательный компонент"
    echo "  ✓ Confluence          — обязательный компонент"
    echo ""
    echo "Дополнительные сервисы (по желанию):"
    echo ""
    
    # Crowd
    echo "  ┌─ Crowd ──────────────────────────────────────────────────────────┐"
    echo "  │  Централизованное управление пользователями и единый вход (SSO). │"
    echo "  │  Позволяет синхронизировать пользователей между Atlassian        │"
    echo "  │  продуктами и предоставляет LDAP-подобную аутентификацию.        │"
    echo "  └──────────────────────────────────────────────────────────────────┘"
    if confirm "Установить Crowd?"; then
        INSTALL_CROWD=true
    fi
    echo ""
    
    # Bitbucket
    echo "  ┌─ Bitbucket ──────────────────────────────────────────────────────┐"
    echo "  │  Git-репозиторий для командной разработки. Поддерживает пулл     │"
    echo "  │  реквесты, code review, CI/CD интеграцию через Pipelines.        │"
    echo "  │  Высокая производительность даже на больших монолитных репо.    │"
    echo "  └──────────────────────────────────────────────────────────────────┘"
    if confirm "Установить Bitbucket?"; then
        INSTALL_BITBUCKET=true
    fi
    echo ""
    
    # Summary
    echo "Выбраны компоненты для установки:"
    echo "  ✓ Jira Software       (обязательный)"
    echo "  ✓ Confluence          (обязательный)"
    $INSTALL_CROWD     && echo "  ✓ Crowd"               || echo "  ✗ Crowd"
    $INSTALL_BITBUCKET && echo "  ✓ Bitbucket"           || echo "  ✗ Bitbucket"
    echo ""
}

# ============================================================================
# Database Configuration (Common credentials)
# ============================================================================

configure_databases() {
    local db_user db_password db_prefix

    echo "--- Настройка базы данных ---"

    db_user=$(prompt_value "Общий пользователь для всех баз данных" "atlassian")
    
    local generated_pass
    generated_pass=$(generate_password)
    db_password=$(prompt_password "Общий пароль для всех баз данных" "$generated_pass")

    db_prefix=$(prompt_value "Префикс для названий баз данных (например: 'atlassian' → atlassian_jiradb)" "atlassian")

    # Write to .env
    {
        # Jira и Confluence — всегда
        echo "JIRA_DB_HOST=jira_db"
        echo "JIRA_DB_NAME=${db_prefix}_jiradb"
        echo "JIRA_DB_USER=$db_user"
        echo "JIRA_DB_PASSWORD=$db_password"

        echo "CONFLUENCE_DB_HOST=confluence_db"
        echo "CONFLUENCE_DB_NAME=${db_prefix}_confluencedb"
        echo "CONFLUENCE_DB_USER=$db_user"
        echo "CONFLUENCE_DB_PASSWORD=$db_password"

        # Опционально
        $INSTALL_CROWD     && echo "CROWD_DB_HOST=crowd_db"     && echo "CROWD_DB_NAME=${db_prefix}_crowddb"     && echo "CROWD_DB_USER=$db_user"     && echo "CROWD_DB_PASSWORD=$db_password"
        $INSTALL_BITBUCKET && echo "BITBUCKET_DB_HOST=bitbucket_db" && echo "BITBUCKET_DB_NAME=${db_prefix}_bitbucketdb" && echo "BITBUCKET_DB_USER=$db_user" && echo "BITBUCKET_DB_PASSWORD=$db_password"
    } >> "$ENV_FILE"
}

# ============================================================================
# JVM Memory Configuration
# ============================================================================

configure_jvm_memory() {
    local jira_mem conf_mem crowd_mem bitb_mem

    echo ""
    echo "--- Настройка JVM памяти ---"

    jira_mem=$(prompt_value "Jira Max Heap (MB)" "2048")
    echo "JIRA_JVM_MAX_MEM=${jira_mem}m" >> "$ENV_FILE"
    echo "JIRA_MEMORY=$((jira_mem * 2))M" >> "$ENV_FILE"

    conf_mem=$(prompt_value "Confluence Max Heap (MB)" "4096")
    echo "CONFLUENCE_JVM_MAX_MEM=${conf_mem}m" >> "$ENV_FILE"
    echo "CONFLUENCE_MEMORY=$((conf_mem * 2))M" >> "$ENV_FILE"

    if $INSTALL_CROWD; then
        crowd_mem=$(prompt_value "Crowd Max Heap (MB)" "2048")
        echo "CROWD_JVM_MAX_MEM=${crowd_mem}m" >> "$ENV_FILE"
        echo "CROWD_MEMORY=$((crowd_mem * 2))M" >> "$ENV_FILE"
    fi

    if $INSTALL_BITBUCKET; then
        bitb_mem=$(prompt_value "Bitbucket Max Heap (MB)" "2048")
        echo "BITBUCKET_JVM_MAX_MEM=${bitb_mem}m" >> "$ENV_FILE"
        echo "BITBUCKET_MEMORY=$((bitb_mem * 2))M" >> "$ENV_FILE"
    fi
}

# ============================================================================
# TLS / Certificates
# ============================================================================

configure_certificates() {
    echo ""
    echo "--- Настройка сертификатов ---"
    
    if confirm "Установить самоподписанные сертификаты OpenSSL?" "y"; then
        echo "USE_CUSTOM_CERTS=true" >> "$ENV_FILE"
        echo "Сертификаты будут сгенерированы в ./certs/"
        echo "Для production замените их на доверенные."
    else
        echo "USE_CUSTOM_CERTS=false" >> "$ENV_FILE"
    fi
}

# ============================================================================
# Reverse Proxy (Traefik) Configuration
# ============================================================================

configure_proxy() {
    echo ""
    echo "--- Настройка Reverse Proxy ---"

    if confirm "Использовать Traefik reverse proxy? (единая точка входа по доменам)" "y"; then

        echo "USE_TRAEFIK=true" >> "$ENV_FILE"

        echo "JIRA_PROXY_NAME=$(prompt_value "Домен для Jira" "jira.local")" >> "$ENV_FILE"
        echo "CONFLUENCE_PROXY_NAME=$(prompt_value "Домен для Confluence" "confluence.local")" >> "$ENV_FILE"

        if $INSTALL_CROWD; then
            echo "CROWD_PROXY_NAME=$(prompt_value "Домен для Crowd" "crowd.local")" >> "$ENV_FILE"
        fi

        if $INSTALL_BITBUCKET; then
            echo "BITBUCKET_PROXY_NAME=$(prompt_value "Домен для Bitbucket" "bitbucket.local")" >> "$ENV_FILE"
        fi
    else
        echo "USE_TRAEFIK=false" >> "$ENV_FILE"
    fi
}

# ============================================================================
# Corporate Proxy Configuration
# ============================================================================

configure_corporate_proxy() {
    echo ""
    echo "--- Настройка корпоративного прокси ---"

    if confirm "Используете корпоративный HTTP прокси?" "n"; then

        local http_proxy https_proxy no_proxy
        local http_host http_port

        http_proxy=$(prompt_value "HTTP Proxy URL" "http://proxy.company.com:8080")

        https_proxy=$(prompt_value "HTTPS Proxy URL" "http://proxy.company.com:8080")

        no_proxy=$(prompt_value "Исключения (через запятую)" "localhost,127.0.0.1,.local,traefik,jira,crowd,confluence,bitbucket")

        {
            echo "HTTP_PROXY=$http_proxy"
            echo "HTTPS_PROXY=$https_proxy"
            echo "NO_PROXY=$no_proxy"
            echo ""
            # Java proxy options
            http_host=$(echo "$http_proxy" | sed -E 's|https?://||' | cut -d: -f1)
            http_port=$(echo "$http_proxy" | sed -E 's|https?://||' | cut -d: -f2)
            echo "JAVA_PROXY_OPTS=-Dhttp.proxyHost=$http_host -Dhttp.proxyPort=$http_port -Dhttps.proxyHost=$http_host -Dhttps.proxyPort=$http_port -Dhttp.nonProxyHosts=localhost|127.0.0.1|*.local"
        } >> "$ENV_FILE"
    fi
}

# ============================================================================
# .env Generation
# ============================================================================

generate_env_file() {
    # Start fresh
    cat > "$ENV_FILE" << 'EOF'
# ============================================================
# Atlassian Ecosystem Configuration
# Auto-generated by install.sh
# ============================================================

# ========== VERSIONS ==========
POSTGRES_TAG=16-alpine
JIRA_VERSION=10.7.3
CROWD_VERSION=7.2-ubuntu-jdk-21
CONFLUENCE_VERSION=10.2.3-ubi9-jdk21
BITBUCKET_VERSION=9.6.2-ubi9-jdk21

# ========== AGENT ==========
AGENT_JAR_PATH=./agent/handler.jar

# ========== PROJECT ==========
COMPOSE_PROJECT_NAME=atlassian

EOF

    echo "# ========== DATABASES ==========" >> "$ENV_FILE"
    configure_databases

    local tz
    tz=$(prompt_value "Часовой пояс" "Europe/Moscow")
    {
        echo ""
        echo "# ========== GENERAL =========="
        echo "TIMEZONE=$tz"
    } >> "$ENV_FILE"

    {
        echo ""
        echo "# ========== JVM MEMORY =========="
    } >> "$ENV_FILE"
    configure_jvm_memory

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

# ============================================================================
# Summary & Deploy
# ============================================================================

show_summary() {
    echo ""
    echo "======================================================================"
    echo "  Конфигурация завершена"
    echo "======================================================================"
    echo ""
    echo "Компоненты:"
    echo "  ✓ Jira Software       (обязательный)"
    echo "  ✓ Confluence          (обязательный)"
    $INSTALL_CROWD     && echo "  ✓ Crowd"               || echo "  ✗ Crowd"
    $INSTALL_BITBUCKET && echo "  ✓ Bitbucket"           || echo "  ✗ Bitbucket"
    echo ""
    echo ".env файл: $ENV_FILE"
    echo ""

    # Generate certificates if requested
    if grep -q "USE_CUSTOM_CERTS=true" "$ENV_FILE" 2>/dev/null; then
        if [ -x "$SCRIPT_DIR/certs/generate-certs.sh" ]; then
            # Collect domains from .env
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

    if confirm "Запустить контейнеры сейчас?" "y"; then
        cd "$SCRIPT_DIR"

        # Determine profile
        if grep -q "USE_TRAEFIK=true" "$ENV_FILE" 2>/dev/null; then
            $COMPOSE_CMD --profile with-proxy up -d
        else
            $COMPOSE_CMD up -d
        fi

        local running=""
        running+="Контейнеры запущены!"
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
        running+="Для логов: $COMPOSE_CMD logs -f"
        running+=$'\n'
        running+="Для остановки: $COMPOSE_CMD down"

        echo ""
        echo "$running"
    else
        echo ""
        echo "Для запуска:"
        echo "  cd $SCRIPT_DIR && $COMPOSE_CMD up -d"
    fi
}

# ============================================================================
# Main
# ============================================================================

cd "$SCRIPT_DIR"

check_deps
select_components
generate_env_file
show_summary

exit 0