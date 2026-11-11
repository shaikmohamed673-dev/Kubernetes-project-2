# 3-Tier App on Kubernetes

The same website + API + database project, now deployed with **Kubernetes**.
Runs locally with **Docker + kind + kubectl** (the cluster itself runs inside Docker).

| Tier | Tech | Kubernetes object | Exposed? |
|---|---|---|---|
| 1 Frontend | Nginx + HTML/JS | Deployment (2 pods) + NodePort Service | Yes, http://localhost:8080 |
| 2 Backend | Node.js 20 + Express | Deployment (2 pods) + ClusterIP Service | No (internal) |
| 3 Database | PostgreSQL 16 | StatefulSet + headless Service + 1Gi PVC | No (internal) |

## Quick start
```bash
./deploy-k8s.sh          # creates cluster, builds images, deploys everything
```
Open http://localhost:8080 and add a message.
Remove everything: `./cleanup-k8s.sh` (app) or `./cleanup-k8s.sh --cluster` (cluster too).

## Repo structure
```
docker-3tier-k8s/
├── README.md
├── deploy-k8s.sh              one-command deploy (kind)
├── cleanup-k8s.sh             teardown
├── kind-config.yaml           local cluster, maps localhost:8080 -> NodePort 30080
├── Dockerfile.frontend        builds the Nginx image
├── Dockerfile.backend         builds the Node.js image (multi-stage)
├── nginx.conf, index.html     Tier 1 code
├── server.js, package.json    Tier 2 code
├── .dockerignore, .gitignore
├── k8s/                       KUBERNETES MANIFESTS
│   ├── 00-namespace.yaml
│   ├── 01-secret.yaml         DB credentials (placeholder!)
│   ├── 02-configmap-init.yaml init.sql for the database
│   ├── 03-database.yaml       headless Service + StatefulSet + PVC
│   ├── 04-backend.yaml        Deployment + Service
│   ├── 05-frontend.yaml       Deployment + NodePort Service
│   └── optional/
│       ├── networkpolicy.yaml tier isolation
│       ├── ingress.yaml       domain routing
│       └── hpa.yaml           autoscaling
└── docs/
    ├── 01-how-docker-works.md
    ├── 02-kubernetes-concepts.md    <- CONCEPTS
    ├── 03-dockerfile-explained.md
    ├── 04-kubectl-commands.md
    ├── 05-manifests-explained.md
    └── 06-deployment-guide.md
```

## What I used
Docker Engine, kind (Kubernetes in Docker), kubectl, Kubernetes manifests (YAML), Nginx 1.27, HTML/CSS/JavaScript, Node.js 20, Express 4.19, pg 8.12, PostgreSQL 16, Alpine Linux, busybox (init container), Bash, Git.
Kubernetes features: Namespace, Secret, ConfigMap, Deployment, StatefulSet, Service (ClusterIP / NodePort / headless), PersistentVolumeClaim, readiness and liveness probes, resource requests and limits, init container, securityContext; optional NetworkPolicy, Ingress, HPA.

## Learning order
1. `docs/01` Docker basics, 2. `docs/02` Kubernetes concepts, 3. `docs/03` Dockerfiles,
4. run `./deploy-k8s.sh`, 5. `docs/04` kubectl commands (try them), 6. `docs/05` manifests line by line, 7. `docs/06` deployment guide.

## Push to your repo
```bash
git init
git add .
git commit -m "3-tier app on Kubernetes"
git branch -M main
git remote add origin https://github.com/<your-user>/docker-3tier-k8s.git
git push -u origin main
```

## Exercises
1. `kubectl delete pod -l app=backend -n three-tier` and watch the Pods come back (self-healing).
2. `kubectl scale deploy/frontend --replicas=4 -n three-tier`.
3. Delete `db-0`: is your message still there? Why? (PVC)
4. Build `app-backend:1.1`, roll it out with `kubectl set image`, then `rollout undo`.
5. Apply `k8s/optional/networkpolicy.yaml` and test `nc -z db 5432` from a frontend Pod.
6. Break the image name on purpose and read the `ImagePullBackOff` events with `describe`.
