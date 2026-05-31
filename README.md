# Atlassian Docker Compose

Full-fledged Docker-compose ecosystem for deploying Atlassian products (Jira, Confluence, Crowd, Bitbucket) with a single entry point via Traefik reverse proxy, SSL support, corporate proxy, and automatic license generation.

## Quick Start

### 1. Interactive installation (recommended)

```bash
cd atlassian-compose
chmod +x install.sh
./install.sh
```

The script will sequentially prompt for:
- Selection of components to install (Jira, Confluence, Crowd, Bitbucket)
- Database settings (common user, password, name prefix)
- JVM memory for each product
- SSL certificates (optional)
- Reverse proxy domains (Traefik)
- Corporate proxy (optional)
- Automatically generates .env file, certificates and starts containers

### 2. Manual installation

1. **Configure the .env file**:
```bash
cp .env.example .env
# Edit .env according to your needs
```

2. **Generate SSL certificates**:
```bash
cd certs
chmod +x generate-certs.sh
./generate-certs.sh
```

3. **Start the containers**:
```bash
docker compose up -d
```

## Access to services

After startup, services are available at the addresses:

| Service    | Direct access         | Via Traefik (HTTPS)             |
| ---------- | --------------------- | ------------------------------- |
| Jira       | http://localhost:8080 | https://jira.local              |
| Crowd      | http://localhost:8095 | https://crowd.local             |
| Confluence | http://localhost:8090 | https://confluence.local        |
| Bitbucket  | http://localhost:7990 | https://bitbucket.local         |
| Traefik    | http://localhost:8081 | https://traefik.local/dashboard |

### Hosts configuration

To access via domains, add to `C:\Windows\System32\drivers\etc\hosts`:
127.0.0.1 jira.local crowd.local confluence.local bitbucket.local traefik.local

## Reverse Proxy (Traefik)

Traefik is configured as a single entry point:
- Single port 80 (HTTP) and 443 (HTTPS) for all services
- Automatic proxying by domain names
- SSL/TLS termination with self-signed certificates
- Health checks for all services
- Traefik Dashboard at traefik.local

### Enabling Traefik

Through install.sh select Traefik usage, or manually set in `.env`:
```env
USE_TRAEFIK=true
```

Traefik is launched only with the `with-proxy` profile:
```bash
# Launch with Traefik
docker compose --profile with-proxy up -d

# Launch without Traefik (only services directly)
docker compose up -d
```

### Labels for Traefik

Services are automatically discovered via Docker labels:
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.jira.rule=Host(`jira.local`)"
  - "traefik.http.routers.jira.entrypoints=websecure"
  - "traefik.http.routers.jira.tls=true"
  - "traefik.http.services.jira.loadbalancer.server.port=8080"
```

## SSL Certificates

The script `certs/generate-certs.sh` automatically creates self-signed certificates for each domain:
```bash
# Generate for all domains by default
./certs/generate-certs.sh

# Generate for specific domains
./certs/generate-certs.sh jira.mycompany.local confluence.mycompany.local
```

For each domain the following is created:
- `{domain}.key` — private key (RSA 4096)
- `{domain}.crt` — self-signed certificate (SHA-256, 10 years)
- `{domain}.pem` — combined PEM bundle
- `ca-bundle.crt` — combined CA bundle for Traefik

### Installing certificates as trusted

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

## Corporate proxy

To work in a corporate network with HTTP proxy:
1. Through install.sh answer "Y" to the question about corporate proxy
2. Or manually edit `proxy.env` and include it in `docker-compose.yml`:
   ```yaml
   env_file:
     - ./proxy.env
   ```

Proxy parameters are passed to container environment variables (`HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`) and to `JAVA_OPTS` for JVM applications.

## Container management

```bash
# View logs
docker compose logs -f jira
docker compose logs -f crowd

# Restart service
docker compose restart jira

# Stop all containers
docker compose down

# Stop and remove volumes (careful!)
docker compose down -v

# Rebuild images (after Dockerfile changes)
docker compose build --no-cache
docker compose up -d
```

## Optimization

The project includes the following optimizations:
- **Dockerfile healthcheck** — each service has a healthcheck for correct readiness determination
- **Resource limits** — memory limits for each container via `deploy.resources.limits.memory`
- **Build context** — a single context `.` for all Dockerfiles, layers are cached
- **Compose profiles** — Traefik is launched only with the `--profile with-proxy` flag

## Requirements

- Docker 24+
- Docker Compose v2+
- OpenSSL (for generating certificates, installed automatically by script)
- Git (optional, for cloning)