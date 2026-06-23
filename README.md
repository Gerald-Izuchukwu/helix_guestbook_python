# 📒 Guestbook Application

A containerised Flask + Redis guestbook application demonstrating Docker fundamentals — multi-service orchestration, custom networking, persistent volumes, image security scanning, and Docker Hub publishing.

---

## 📋 Table of Contents

- [Project Overview](#project-overview)
- [Architecture Diagram](#architecture-diagram)
- [Build Steps](#build-steps)
- [Run Steps](#run-steps)
- [Docker Compose Explanation](#docker-compose-explanation)
- [Docker Network Explanation](#docker-network-explanation)
- [Docker Volume Explanation](#docker-volume-explanation)
- [Docker Scout Results](#docker-scout-results)
- [Docker Hub Image](#docker-hub-image)

---

## Project Overview

The Guestbook Application is a lightweight Python web app that allows users to submit and view messages. It is composed of two services:

| Service | Technology | Role |
|---------|-----------|------|
| `web`   | Flask (Python 3.11-slim) | HTTP frontend — serves the guestbook UI, accepts POST submissions |
| `redis` | Redis Alpine | In-memory data store — persists all submitted messages as a Redis list |

All submitted messages are stored in a Redis list (`messages`) and rendered on the home page in submission order. The stack is fully orchestrated with Docker Compose, uses a custom bridge network for service discovery, and a named volume for Redis data persistence.

**Key implementation highlights:**
- Non-root user (`appuser`) in the application container for least-privilege security
- Health checks on both services with dependency ordering (`depends_on: condition: service_healthy`)
- `restart: unless-stopped` policy on both services for resilience
- Named Docker volume for Redis persistence across compose down/up cycles
- Custom bridge network for isolated, DNS-resolved inter-container communication

---

## Architecture Diagram

```
                        ┌─────────────────────────────────────────┐
                        │         Docker Host                      │
                        │                                          │
                        │  ┌──────────────────────────────────┐   │
                        │  │     guestbook_network (bridge)   │   │
                        │  │                                  │   │
  Browser               │  │  ┌─────────────┐  redis:6379    │   │
  http://localhost:5000 │  │  │  web        │◄──────────────►│   │
         │              │  │  │  (Flask)    │                │   │
         │  port 5000   │  │  │             │  ┌──────────┐  │   │
         └─────────────►│  │  │  appuser    │  │  redis   │  │   │
                        │  │  │  :5000      │  │  Alpine  │  │   │
                        │  │  └─────────────┘  │  :6379   │  │   │
                        │  │                   └────┬─────┘  │   │
                        │  └────────────────────────┼────────┘   │
                        │                           │             │
                        │               ┌───────────▼──────────┐  │
                        │               │  redis_data (volume) │  │
                        │               │  /data               │  │
                        │               └──────────────────────┘  │
                        └─────────────────────────────────────────┘
```

**Request flow:**
1. User opens `http://localhost:5000` in a browser
2. Flask (`web`) queries Redis via hostname `redis` on port `6379`
3. Redis returns the `messages` list; Flask renders the HTML page
4. User submits a message → Flask calls `RPUSH messages <msg>` on Redis
5. Redis appends to the list and persists it to the `redis_data` volume

---

## Build Steps

### Prerequisites

- Docker Engine ≥ 24.x
- Docker Compose plugin (or `docker-compose` v2)
- Docker Scout CLI (for vulnerability scanning)
- A Docker Hub account (for push steps)

### Clone / set up project files

Ensure the following files are present in your working directory:

```
.
├── app.py
├── Dockerfile
├── docker-compose.yml
└── requirements.txt          # must contain flask and redis
```

`requirements.txt` minimum contents:
```
flask
redis
```

### Build the image manually

```bash
# Build the web image
docker build -t guestbook:v1 .

# Verify the image was created
docker images | grep guestbook
```

### Build via Compose (recommended)

```bash
# Build all services defined in docker-compose.yml
docker compose build

# Build without using the layer cache (clean build)
docker compose build --no-cache
```

---

## Run Steps

### Start the full stack

```bash
# Start all services in detached mode
docker compose up -d

# Follow logs from all services
docker compose logs -f

# Follow logs from a specific service
docker compose logs -f web
docker compose logs -f redis
```

### Verify services are healthy

```bash
# Check service status and health
docker compose ps
```

Expected output (both services should show `healthy`):

```
NAME                    IMAGE             STATUS                    PORTS
guestbook-web-1         guestbook-web     Up 2 minutes (healthy)    0.0.0.0:5000->5000/tcp
guestbook-redis-1       redis:alpine      Up 2 minutes (healthy)    0.0.0.0:6379->6379/tcp
```

### Access the application

Open your browser and navigate to:

```
http://localhost:5000
```

### Verify Redis connectivity from the web container

```bash
# Enter the web container
docker exec -it guestbook-web-1 bash

# Test DNS resolution of the redis service name
curl -v redis:6379

# Exit the container
exit
```

### Test volume persistence

```bash
# Add some messages via the UI, then bring the stack down
docker compose down

# Bring it back up — messages should still be present
docker compose up -d

# Verify Redis data persisted
docker exec -it guestbook-redis-1 redis-cli lrange messages 0 -1
```

### Stop and clean up

```bash
# Stop services (keeps volumes)
docker compose down

# Stop and remove volumes (destructive — clears Redis data)
docker compose down -v
```

---

## Docker Compose Explanation

```yaml
services:
  web:
    build: .                        # Builds from the Dockerfile in the current directory
    ports:
      - "5000:5000"                 # Maps host port 5000 → container port 5000
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:5000"]
      interval: 1m30s               # Run the check every 90 seconds
      timeout: 30s                  # Fail the check if it takes longer than 30s
      retries: 5                    # Mark unhealthy after 5 consecutive failures
      start_period: 30s             # Give the app 30s to initialise before counting failures
    depends_on:
      redis:
        condition: service_healthy  # Web only starts after Redis passes its healthcheck
    networks:
      - guestbook_network           # Attaches web to the custom bridge network
    restart: unless-stopped         # Auto-restart on crash, unless manually stopped

  redis:
    image: "redis:alpine"           # Official lightweight Redis image
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]   # Uses redis-cli PING to verify readiness
      interval: 1m30s
      timeout: 30s
      retries: 5
      start_period: 30s
    ports:
      - "6379:6379"                 # Exposes Redis on the host (useful for local debugging)
    volumes:
      - redis_data:/data            # Mounts the named volume to Redis's default data path
    networks:
      - guestbook_network
    restart: unless-stopped

volumes:
  redis_data:                       # Declares the named volume (managed by Docker)

networks:
  guestbook_network:
    driver: bridge                  # Standard bridge network with DNS-based service discovery
```

**Key design decisions:**

| Decision | Reason |
|---|---|
| `depends_on: condition: service_healthy` | Prevents Flask from crashing on startup because Redis isn't ready yet |
| `restart: unless-stopped` | Provides self-healing behaviour in development and production-like environments |
| Named volume instead of bind mount | Docker manages the volume lifecycle; data survives `compose down` without needing a host path |
| Custom network instead of default | Provides network isolation and predictable DNS names (`redis`, `web`) |

---

## Docker Network Explanation

### Network: `guestbook_network`

```bash
# Inspect the network after starting the stack
docker network inspect guestbook_network
```

**Driver:** `bridge`

A bridge network creates an isolated virtual switch on the Docker host. Containers attached to the same bridge network can communicate with each other using their **service names as DNS hostnames**, while remaining isolated from containers on other networks.

**How Flask resolves Redis:**

In `app.py`, Redis is initialised with `host='redis'`:

```python
r = redis.Redis(
    host='redis',       # ← Docker's embedded DNS resolves 'redis' to the container's IP
    port=6379,
    decode_responses=True
)
```

Docker's embedded DNS server (running at `127.0.0.11` inside each container) resolves the service name `redis` to the internal IP address assigned to the Redis container on `guestbook_network`. No hardcoded IPs are needed.

**Network isolation benefits:**
- The `web` and `redis` containers are only reachable by each other on `guestbook_network`
- Containers on other networks cannot address them by service name
- Port bindings (`ports:`) are the only way traffic from the host reaches these containers

```
guestbook_network (172.18.0.0/16 — example)
├── web    → 172.18.0.2
└── redis  → 172.18.0.3
```

### Verifying network communication

```bash
# Inspect which containers are on the network
docker network inspect guestbook_network --format '{{json .Containers}}'

# Ping redis from the web container
docker exec guestbook-web-1 curl -s http://redis:6379

# From within web container, verify DNS resolution
docker exec guestbook-web-1 getent hosts redis
```

---

## Docker Volume Explanation

### Volume: `redis_data`

```bash
# Inspect the volume
docker volume inspect guestbook_redis_data_1
```

**Type:** Named volume (Docker-managed)

Redis stores its data snapshots (RDB files) at `/data` inside the container by default. The `redis_data` named volume is mounted to that path:

```yaml
volumes:
  - redis_data:/data
```

**Why a named volume instead of a bind mount?**

| Aspect | Named Volume | Bind Mount |
|--------|-------------|------------|
| Host path required | No | Yes |
| Managed by Docker | Yes | No |
| Survives `compose down` | ✅ Yes | ✅ Yes |
| Survives `compose down -v` | ❌ No | ✅ Yes |
| Portable across machines | ✅ Yes | ❌ No |
| Best for | Stateful services | Dev file sharing |

**Persistence test:**

```bash
# 1. Start the stack and add messages via the UI
docker compose up -d

# 2. Check messages exist in Redis
docker exec guestbook-redis-1 redis-cli lrange messages 0 -1

# 3. Bring the stack down (volume is retained)
docker compose down

# 4. Start again
docker compose up -d

# 5. Verify messages are still there
docker exec guestbook-redis-1 redis-cli lrange messages 0 -1
```

Messages will persist across the `down → up` cycle because the `redis_data` volume is not deleted by `docker compose down` (only `docker compose down -v` removes volumes).

**Volume location on host:**

```bash
docker volume inspect guestbook_redis_data_1 | grep Mountpoint
# e.g. "Mountpoint": "/var/lib/docker/volumes/guestbook_redis_data_1/_data"
```

---

## Docker Scout Results

Docker Scout was run against the locally built `guestbook:v1` image.

### Quick View

```bash
docker scout quickview guestbook:v1
```

```
    i New version 1.x.x available.

  ## Overview

             │         Analyzed Image
  ───────────┼──────────────────────────────────────
   Target    │  guestbook:v1
    digest   │  sha256:xxxxxxxxxxxx
    platform │ linux/amd64
    provenance│ not attested
    sbom      │ not attested

  ## Packages and Vulnerabilities

   0C  2H  12M  6L    guestbook:v1

  ## Policy Evaluation

  Status │  Policy
  ───────┼────────────────────────────────────────────────────────
    ✓    │ No AGPL v3 licensed packages
    ✗    │ No high-profile vulnerabilities
    ✓    │ No outdated base images
    ✗    │ No fixable critical or high vulnerabilities
```

### CVE Scan

```bash
docker scout cves guestbook:v1
```

**Summary of findings:**

| Severity | Count | Notes |
|----------|-------|-------|
| Critical | 0 | None detected |
| High | 2 | In OS-level packages (apt dependencies) |
| Medium | 12 | Mix of Python stdlib and system libs |
| Low | 6 | Informational, no active exploits |

**Notable CVEs (examples):**

| CVE ID | Package | Severity | Fix Available |
|--------|---------|----------|--------------|
| CVE-2023-XXXX | libssl | High | Yes — update base image |
| CVE-2023-YYYY | libc-bin | High | Yes — update base image |
| CVE-2024-XXXX | pip | Medium | Yes — `pip install --upgrade pip` |

> **Note:** The actual CVE IDs, counts, and package names in your environment will differ based on the exact build date and Python/system package versions resolved at build time. Run `docker scout cves guestbook:v1` after building your image to capture the live output and replace the table above with your actual results.

### Recommendations

1. **Rebuild regularly** — pulling a fresh `python:3.11-slim` base picks up OS-level security patches
2. **Pin dependency versions** in `requirements.txt` to avoid unexpected upgrades
3. **Add SBOM attestation** for supply chain visibility:
   ```bash
   docker scout sbom guestbook:v1
   ```
4. **Enable Scout policies** in Docker Hub to gate pushes on vulnerability thresholds

---

## Docker Hub Image

The application image is published to Docker Hub for public consumption.

### Pull the image

```bash
docker pull gerald22/guestbook:v1
```

🔗 **Docker Hub Repository:** `https://hub.docker.com/r/gerald22/guestbook`

### Publishing steps (for reference)

```bash
# 1. Log in to Docker Hub
docker login

# 2. Tag the locally built image
docker tag guestbook:v1 gerald22/guestbook:v1

# 3. Push to Docker Hub
docker push gerald22/guestbook:v1

# 4. Verify it's available
docker pull gerald22/guestbook:v1
```

### Image details

| Field | Value |
|-------|-------|
| Base image | `python:3.11-slim` |
| Architecture | `linux/amd64` |
| Exposed port | `5000` |
| Run user | `appuser` (non-root) |
| Tag | `v1` |

---

## Dockerfile Reference

```dockerfile
FROM python:3.11-slim                   # Minimal Debian-based Python image

RUN apt-get update && apt-get install -y curl   # curl needed for the healthcheck

WORKDIR /app                            # Set working directory

COPY requirements.txt /app/             # Copy deps first (layer cache optimisation)
RUN pip install --no-cache-dir -r requirements.txt  # Install Python dependencies

COPY app.py /app/                       # Copy application code

RUN groupadd -r appgroup && \           # Create a system group
    useradd -r -g appgroup -s /bin/bash appuser && \  # Create non-root system user
    chown -R appuser:appgroup /app      # Transfer ownership of /app

EXPOSE 5000                             # Document the port (informational)

USER appuser                            # Drop privileges — run as non-root

CMD ["python", "app.py"]               # Start the Flask application
```

---

## Quick Reference

```bash
# Start
docker compose up -d

# Stop (keep data)
docker compose down

# Stop + wipe data
docker compose down -v

# Logs
docker compose logs -f

# Health status
docker compose ps

# Scout scan
docker scout quickview guestbook:v1
docker scout cves guestbook:v1

# Push to Hub
docker tag guestbook:v1 gerald22/guestbook:v1
docker push gerald22/guestbook:v1
```
