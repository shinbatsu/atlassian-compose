# Atlassian Docker Compose

Полноценная Docker-compose экосистема для развёртывания Atlassian продуктов (Jira, Confluence, Crowd, Bitbucket) с единой точкой входа через Traefik reverse proxy, поддержкой SSL, корпоративного прокси и автоматической генерации лицензий.

## Архитектура

```
                         ┌──────────────────────┐
                         │      Traefik          │
                         │   (Reverse Proxy)     │
                         │   :80 / :443 (HTTPS)  │
                         └────┬──────┬──────┬────┘
                              │      │      │
                     ┌────────┘      │      └─────────┐─────────────┐
                     ▼               ▼                ▼             ▼
               ┌──────────┐  ┌──────────┐   ┌──────────────┐  ┌──────────┐
               │   Jira   │  │  Crowd   │   │  Confluence  │  │ Bitbucket│
               │ :8080    │  │ :8095    │   │ :8090        │  │ :7990    │
               └────┬─────┘  └────┬─────┘   └──────┬───────┘  └────┬─────┘
                    │             │                │               │
                    └─────────────┼────────────────┼───────────────┘
                                  │                │
                            ┌─────▼──────┐   ┌─────▼──────┐
                            │ PostgreSQL │   │ PostgreSQL │
                            │   (Jira)   │   │  (Crowd)   │
                            └────────────┘   └────────────┘
                            ┌─────▼───────┐  ┌─────▼──────┐
                            │ PostgreSQL  │  │ PostgreSQL │
                            │ (Confluence)│  │ (Bitbucket)│
                            └─────────────┘  └────────────┘
```

## Быстрый старт

### 1. Интерактивная установка (рекомендуется)

```bash
cd atlassian-compose
chmod +x install.sh
./install.sh
```

Скрипт последовательно запросит:
- Выбор компонентов для установки (Jira, Confluence, Crowd, Bitbucket)
- Настройки БД (общий пользователь, пароль, префикс названий)
- JVM память для каждого продукта
- SSL сертификаты (опционально)
- Reverse proxy домены (Traefik)
- Корпоративный прокси (опционально)
- Автоматически сгенерирует .env файл, сертификаты и запустит контейнеры

### 2. Ручная установка

1. **Настройте .env файл**:
   ```bash
   cp .env.example .env
   # Отредактируйте .env под свои нужды
   ```

2. **Сгенерируйте SSL сертификаты**:
   ```bash
   cd certs
   chmod +x generate-certs.sh
   ./generate-certs.sh
   ```

3. **Запустите контейнеры**:
   ```bash
   docker compose up -d
   ```


## Доступ к сервисам

После запуска сервисы доступны по адресам:

| Сервис     | Прямой доступ         | Через Traefik (HTTPS)           |
| ---------- | --------------------- | ------------------------------- |
| Jira       | http://localhost:8080 | https://jira.local              |
| Crowd      | http://localhost:8095 | https://crowd.local             |
| Confluence | http://localhost:8090 | https://confluence.local        |
| Bitbucket  | http://localhost:7990 | https://bitbucket.local         |
| Traefik    | http://localhost:8081 | https://traefik.local/dashboard |

### Настройка hosts

Для доступа по доменам добавьте в `C:\Windows\System32\drivers\etc\hosts`:
```
127.0.0.1 jira.local crowd.local confluence.local bitbucket.local traefik.local
```

## Reverse Proxy (Traefik)

Traefik настроен как единая точка входа:

- Единый порт 80 (HTTP) и 443 (HTTPS) для всех сервисов
- Автоматическое проксирование по доменным именам
- SSL/TLS termination с самоподписанными сертификатами
- Health checks для всех сервисов
- Traefik Dashboard на traefik.local

### Включение Traefik

Через install.sh выберите использование Traefik, или вручную установите в `.env`:
```env
USE_TRAEFIK=true
```

Traefik запускается только с профилем `with-proxy`:
```bash
# Запуск с Traefik
docker compose --profile with-proxy up -d

# Запуск без Traefik (только сервисы напрямую)
docker compose up -d
```

### Метки (labels) для Traefik

Сервисы автоматически обнаруживаются через Docker labels:
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.jira.rule=Host(`jira.local`)"
  - "traefik.http.routers.jira.entrypoints=websecure"
  - "traefik.http.routers.jira.tls=true"
  - "traefik.http.services.jira.loadbalancer.server.port=8080"
```

## SSL Сертификаты

Скрипт `certs/generate-certs.sh` автоматически создаёт самоподписанные сертификаты для каждого домена:

```bash
# Генерация для всех доменов по умолчанию
./certs/generate-certs.sh

# Генерация для конкретных доменов
./certs/generate-certs.sh jira.mycompany.local confluence.mycompany.local
```

Для каждого домена создаётся:
- `{domain}.key` — закрытый ключ (RSA 4096)
- `{domain}.crt` — самоподписанный сертификат (SHA-256, 10 лет)
- `{domain}.pem` — объединённый PEM bundle
- `ca-bundle.crt` — объединённый CA bundle для Traefik

### Установка сертификатов в доверенные

**Windows (PowerShell Admin):**
```powershell
Get-ChildItem -Path .\certs\*.crt | Import-Certificate -CertStoreLocation Cert:\LocalMachine\Root
```

**Linux:**
```bash
sudo cp certs/*.crt /usr/local/share/ca-certificates/ && sudo update-ca-certificates
```

**macOS:**
```bash
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain certs/*.crt
```

## Корпоративный прокси

Для работы в корпоративной сети с HTTP прокси:

1. Через install.sh ответьте "Y" на вопрос о корпоративном прокси
2. Или вручную отредактируйте `proxy.env` и подключите его в `docker-compose.yml`:
   ```yaml
   env_file:
     - ./proxy.env
   ```

Параметры прокси передаются в переменные окружения контейнеров (`HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`) и в `JAVA_OPTS` для JVM-приложений.

## Управление контейнерами

```bash
# Просмотр логов
docker compose logs -f jira
docker compose logs -f crowd

# Перезапуск сервиса
docker compose restart jira

# Остановка всех контейнеров
docker compose down

# Остановка с удалением томов (осторожно!)
docker compose down -v

# Пересборка образов (после изменений Dockerfile)
docker compose build --no-cache
docker compose up -d
```

## Оптимизация

Проект включает следующие оптимизации:

- **Dockerfile healthcheck** — каждый сервис имеет healthcheck для корректного определения готовности
- **Resource limits** — лимиты памяти для каждого контейнера через `deploy.resources.limits.memory`
- **Build context** — единый context `.` для всех Dockerfile, слои кешируются
- **Профили Compose** — Traefik запускается только с флагом `--profile with-proxy`

## Требования

- Docker 24+
- Docker Compose v2+
- OpenSSL (для генерации сертификатов, устанавливается автоматически скриптом)
- Git (опционально, для клонирования)