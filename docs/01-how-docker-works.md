# 1. How Docker Works

## The problem Docker solves
"It works on my machine" — your laptop has Node 20, the server has Node 14, and the app breaks.
Docker packages your app **with everything it needs** (runtime, libraries, config) so it runs the same everywhere.

## Core ideas

| Concept | Meaning | Analogy |
|---|---|---|
| **Image** | Read-only template: OS files + runtime + your code | A recipe / class |
| **Container** | A running instance of an image (isolated process) | A cooked dish / object |
| **Dockerfile** | Text file with steps to build an image | The recipe's written steps |
| **Registry** | Server storing images (Docker Hub, GHCR) | GitHub for images |
| **Volume** | Storage that outlives a container | External hard disk |
| **Network** | Private virtual network between containers | A private LAN |
| **Docker Engine (daemon)** | Background service that builds/runs everything | The kitchen |
| **Docker CLI** | The `docker` command you type | The waiter giving orders |
| **Compose** | Runs multi-container apps from one YAML file | A full menu order |

## What happens when you type `docker run nginx`
1. CLI sends the request to the Docker daemon.
2. Daemon looks for image `nginx` locally. Not found -> pulls it from Docker Hub.
3. Daemon creates a container from the image (adds a thin writable layer on top).
4. Gives it its own network, filesystem view and process space.
5. Starts the main process (nginx).

## Containers vs Virtual Machines
- VM = full guest OS + kernel per app (GBs, slow boot).
- Container = shares the host kernel, isolated using Linux **namespaces** (what it can see)
  and **cgroups** (how much CPU/RAM it can use). MBs, starts in seconds.

## Image layers
Each Dockerfile instruction creates a **layer**. Layers are cached and shared.
If you change only `server.js`, Docker reuses all earlier layers -> fast rebuilds.
This is why we `COPY package.json` and `npm install` BEFORE copying source code.

## 3-Tier architecture in this project

```
 Browser
    |  http://localhost:8080
    v
+----------------------+   frontend-net   +----------------------+   backend-net   +----------------------+
| TIER 1: frontend     | ---------------> | TIER 2: backend      | --------------> | TIER 3: db           |
| Nginx (HTML + proxy) |                  | Node.js + Express    |                 | PostgreSQL + volume  |
| port 80 -> host 8080 |                  | port 3000 (internal) |                 | port 5432 (internal) |
+----------------------+                  +----------------------+                 +----------------------+
```

- Only the **frontend** is published to the outside world.
- The **database** is on `backend-net` only: the frontend and the internet cannot reach it. This is real tier isolation.
- Containers find each other by **service name** (`backend`, `db`) through Docker's built-in DNS.
