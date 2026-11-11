# 3. Dockerfiles — Every Line Explained

These Dockerfiles build the images that Kubernetes runs. Kubernetes does not read Dockerfiles itself.

## Dockerfile instruction reference
| Instruction | Purpose |
|---|---|
| `FROM` | Base image to start from. Every Dockerfile starts here |
| `WORKDIR` | Set working directory (creates it). Later commands run here |
| `COPY` | Copy files from your machine into the image |
| `ADD` | Like COPY + extract tar / download URL (prefer COPY) |
| `RUN` | Execute a command **at build time** (install packages). Creates a layer |
| `ENV` | Set an environment variable (build + runtime) |
| `ARG` | Variable available only at build time |
| `EXPOSE` | Documents the port the app listens on (does NOT publish it) |
| `USER` | Run following commands/process as this user (not root) |
| `HEALTHCHECK` | Command Docker runs periodically to test if app is healthy |
| `CMD` | Default command when container **starts** (can be overridden) |
| `ENTRYPOINT` | Fixed executable; CMD becomes its arguments |
| `VOLUME` | Declares a mount point for persistent data |

`RUN` = build time. `CMD` = run time. This is the most common confusion.

---

## Backend Dockerfile (`Dockerfile.backend`) — multi-stage

```dockerfile
FROM node:20-alpine AS deps
```
Start from the official Node 20 image on Alpine Linux (about 5 MB base, small and secure).
`AS deps` names this stage so we can copy from it later.

```dockerfile
WORKDIR /app
```
Create `/app` inside the image and `cd` into it. All next commands run there.

```dockerfile
COPY package.json ./
```
Copy ONLY package.json first. Docker caches this layer; if dependencies didn't change,
the slow `npm install` below is skipped on rebuilds.

```dockerfile
RUN npm install --omit=dev
```
Install production dependencies only (skips devDependencies) -> smaller image.

```dockerfile
FROM node:20-alpine
```
Start a **second, fresh stage**. Everything from stage 1 is discarded unless we copy it.
Result: the final image has no build leftovers or npm cache.

```dockerfile
WORKDIR /app
```
Same working directory in the final image.

```dockerfile
ENV NODE_ENV=production
```
Tells Express and libraries to run in optimized production mode.

```dockerfile
COPY --from=deps /app/node_modules ./node_modules
```
Copy the installed modules from stage `deps` into this final image.

```dockerfile
COPY server.js ./
```
Copy the app source LAST, because it changes most often (keeps earlier layers cached).

```dockerfile
USER node
```
Run as the unprivileged `node` user. If the app is hacked, the attacker is not root.

```dockerfile
EXPOSE 3000
```
Documentation: this app listens on 3000. Other containers can reach it on that port in the network.

```dockerfile
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/api/health || exit 1
```
Every 15s call `/api/health`. 3s timeout. Ignore failures for the first 10s (startup).
After 3 failures the container is marked `unhealthy`. (Kubernetes ignores this instruction and uses its own readiness/liveness probes; it is kept so the image also works with plain Docker.) `|| exit 1` makes failure return a non-zero code.

```dockerfile
CMD ["node", "server.js"]
```
Command executed when the container starts. JSON (exec) form runs node directly as PID 1,
so it receives stop signals properly.

---

## Frontend Dockerfile (`Dockerfile.frontend`)

```dockerfile
FROM nginx:1.27-alpine
```
Base: Nginx web server on Alpine. Version is pinned (never rely on `latest` in production).

```dockerfile
COPY nginx.conf /etc/nginx/conf.d/default.conf
```
Replace the default site config with ours (serves the page and proxies `/api/` to `backend:3000`).

```dockerfile
COPY index.html /usr/share/nginx/html/index.html
```
Put our website in Nginx's default web root.

```dockerfile
EXPOSE 80
```
Nginx listens on 80 inside the container (it is exposed outside by the Kubernetes Service, see 05-manifests-explained.md).

```dockerfile
HEALTHCHECK --interval=15s --timeout=3s --retries=3 \
  CMD wget -qO- http://localhost/ || exit 1
```
Checks the homepage loads.

(No `CMD` needed: the nginx base image already defines one that starts nginx.)

---

## `.dockerignore` — why (one shared file for this folder)
Lists files NOT sent to the build (`node_modules`, `.git`, `.env`).
Smaller build context = faster builds, and secrets never end up inside images.
