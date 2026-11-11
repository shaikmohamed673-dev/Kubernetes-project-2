# 2. Kubernetes Concepts

## Why Kubernetes when Docker already works?
Docker runs containers on **one machine**. In production you also need:
- Restart a container automatically if it crashes
- Run 3 copies for load and spread them over many servers
- Roll out a new version with zero downtime, and roll back if it is bad
- Scale up when traffic grows
- Give services stable names even though containers get new IPs
- Store passwords and config safely

**Kubernetes (K8s)** is a system that manages containers across many machines to do all of this.
You do not say "run this container". You say "I want 2 copies of this running, always" and Kubernetes makes it so.

> Docker = builds and runs containers. Kubernetes = manages (orchestrates) many containers.
> Kubernetes still needs Docker-style images. The Dockerfiles in this project are unchanged.

---

## 1. Architecture of a cluster

```
                         CLUSTER
 +------------- CONTROL PLANE (the brain) -------------+
 |  API Server  <-- every kubectl command goes here     |
 |  etcd        database that stores the cluster state  |
 |  Scheduler   decides WHICH node runs each Pod         |
 |  Controller Manager  keeps actual state = desired     |
 +-------------------------------------------------------+
        |                      |                     |
 +--- WORKER NODE 1 ---+ +--- WORKER NODE 2 ---+ +--- NODE 3 ---+
 | kubelet             | | kubelet             | | kubelet       |
 | kube-proxy          | | kube-proxy          | | kube-proxy    |
 | container runtime   | | container runtime   | | ...           |
 | [Pod][Pod]          | | [Pod][Pod]          | |               |
 +---------------------+ +---------------------+ +---------------+
```

| Component | Job |
|---|---|
| **API Server** | The single front door. kubectl, the scheduler and kubelets all talk through it |
| **etcd** | Key-value store holding all cluster data (what should exist) |
| **Scheduler** | Picks a node for each new Pod based on free CPU/RAM and rules |
| **Controller Manager** | Runs control loops (Deployment controller, etc.) |
| **kubelet** | Agent on each node: starts containers, runs probes, reports status |
| **kube-proxy** | Sets up network rules so Services reach their Pods |
| **Container runtime** | Actually runs containers (containerd). Docker images work as-is |

## 2. The most important idea: desired state and the reconciliation loop
You write YAML that describes the **desired state** ("2 backend Pods"). You send it with `kubectl apply`.
Controllers constantly compare **actual state** with **desired state** and fix any difference:

```
You: replicas: 2  -->  API Server  -->  etcd
Controller sees only 1 Pod running  -->  creates 1 more
A Pod crashes                       -->  creates a replacement
A node dies                         -->  reschedules its Pods on other nodes
```
This is called **self-healing**, and is the reason to use Kubernetes.

## 3. What happens on `kubectl apply -f k8s/`
1. kubectl sends the YAML to the API Server (authenticated).
2. API Server validates it and saves it in etcd.
3. Deployment controller creates a ReplicaSet, which creates Pod objects.
4. Scheduler assigns each Pod to a node.
5. kubelet on that node pulls the image and starts the container.
6. Probes pass -> Pod becomes Ready -> Service starts sending traffic to it.

---

## 4. Objects (building blocks)

### Pod
Smallest unit. Wraps **one or more containers** that share network (same IP, `localhost`) and storage.
Pods are **temporary**: when one dies it is replaced by a NEW Pod with a NEW IP. You rarely create Pods directly.

### ReplicaSet
Keeps N identical Pods running. Created for you by a Deployment.

### Deployment
For **stateless** apps (frontend, backend). Gives you replicas, rolling updates and rollback.
Update the image -> it creates a new ReplicaSet and gradually replaces Pods (zero downtime).

### StatefulSet
For **stateful** apps (databases). Gives Pods stable names (`db-0`), stable storage and ordered start/stop.
Each Pod gets its own PersistentVolumeClaim via `volumeClaimTemplates`.

| | Deployment | StatefulSet |
|---|---|---|
| Pod names | random (`backend-7d9f-xk2`) | fixed (`db-0`) |
| Storage | shared or none | own volume per Pod, kept on restart |
| Use for | web, API | databases, queues |

### Service
Pods come and go, so their IPs change. A **Service** is a stable name + IP that load-balances to all matching Pods (found by **labels**). Inside the cluster, DNS name = service name (`backend`, `db`).

| Type | Reachable from | Use |
|---|---|---|
| **ClusterIP** (default) | inside cluster only | backend, internal services |
| **NodePort** | outside, via `nodeIP:30000-32767` | local testing (our frontend) |
| **LoadBalancer** | outside, via cloud load balancer | production on AWS/Azure/GCP |
| **Headless** (`clusterIP: None`) | DNS returns Pod IPs directly | StatefulSets / databases |

### Labels and selectors
Labels are key/value tags on objects (`app: backend`). Selectors find objects by label.
A Service uses `selector: app: backend` to know which Pods to send traffic to. Wrong label = no traffic.

### Namespace
A virtual folder inside the cluster to group and isolate resources (`three-tier`). Lets teams/environments share a cluster.

### ConfigMap
Non-secret configuration (files or key/values). We use one to hold `init.sql`.

### Secret
Sensitive data (passwords, tokens). Same idea as ConfigMap but treated more carefully (hidden in output, access-controlled).
NOTE: values are only **base64-encoded, not encrypted**, unless you enable encryption at rest. Never commit real secrets to Git.

### Volume, PersistentVolume (PV), PersistentVolumeClaim (PVC), StorageClass
- Container disk disappears with the Pod. Databases need storage that survives.
- **PVC** = a Pod's request for storage ("I need 1Gi").
- **PV** = the actual disk. **StorageClass** creates PVs automatically on demand (dynamic provisioning).
- Docker equivalent: named volume.

### Probes (health checks)
| Probe | Question | If it fails |
|---|---|---|
| **readinessProbe** | Can this Pod receive traffic yet? | Removed from Service endpoints (not restarted) |
| **livenessProbe** | Is it stuck/dead? | Container is restarted |
| **startupProbe** | Has a slow app finished starting? | Delays the other probes |

Kubernetes ignores the Dockerfile `HEALTHCHECK`. It uses these probes instead.

### Resource requests and limits
- **requests**: guaranteed minimum; used by the Scheduler to place the Pod.
- **limits**: maximum allowed. Over the memory limit -> container is killed (OOMKilled). Over CPU limit -> throttled.
- `100m` CPU = 0.1 core. `256Mi` = 256 mebibytes.

### Init container
Runs to completion BEFORE the main container. We use one to wait until the database port is open.

### Ingress
Rules for routing external HTTP(S) traffic (by host/path) to Services, with TLS. Needs an **Ingress controller** (e.g. ingress-nginx). One entry point for many apps.

### NetworkPolicy
Firewall rules between Pods. We use it so only the backend can reach the database.
Works only if the cluster's network plugin enforces it (Calico, Cilium).

### HorizontalPodAutoscaler (HPA)
Automatically changes replica count based on CPU/memory (needs metrics-server).

### Others you will meet later
Job / CronJob (run-to-completion and scheduled tasks), DaemonSet (one Pod per node), RBAC (who can do what), ServiceAccount (identity for Pods), Helm (package manager for K8s YAML), Kustomize (overlay config per environment).

---

## 5. Rolling update and rollback
With `replicas: 2`, updating the image does this: start 1 new Pod -> wait until Ready -> stop 1 old Pod -> repeat.
Users never see downtime. If the new version is broken: `kubectl rollout undo deployment/backend`.

## 6. Networking rules (flat network)
- Every Pod gets its own IP; any Pod can reach any Pod (unless a NetworkPolicy blocks it).
- Inside the cluster you use Service DNS names: `backend`, `db`, or the full form `backend.three-tier.svc.cluster.local`.
- Our Nginx config says `proxy_pass http://backend:3000` — **unchanged from Docker**, because the Service is also called `backend`.

---

## 7. Docker Compose -> Kubernetes mapping (this project)

| Docker Compose | Kubernetes | File |
|---|---|---|
| project / network | Namespace | `00-namespace.yaml` |
| `.env` variables | Secret | `01-secret.yaml` |
| `init.sql` bind mount | ConfigMap + volume mount | `02-configmap-init.yaml` |
| `db` service + named volume | StatefulSet + PVC + headless Service | `03-database.yaml` |
| `depends_on: service_healthy` | initContainer + readinessProbe | `04-backend.yaml` |
| `backend` service | Deployment (2 replicas) + ClusterIP Service | `04-backend.yaml` |
| `frontend` + `ports: 8080:80` | Deployment (2 replicas) + NodePort Service | `05-frontend.yaml` |
| `restart: unless-stopped` | built in: Deployment always replaces dead Pods | n/a |
| `healthcheck` | readiness / liveness probes | each file |
| two networks for isolation | NetworkPolicy | `optional/networkpolicy.yaml` |
| `docker compose up -d` | `kubectl apply -f k8s/` | n/a |
| `docker compose logs` | `kubectl logs` | n/a |

## 8. Our architecture on Kubernetes
```
 Browser -> localhost:8080 -> (kind port map) -> NodePort 30080
                                     |
                       Service "frontend" (NodePort)
                          /                     \
                 Pod frontend-1             Pod frontend-2        <- Deployment, Nginx
                          \                     /
                       Service "backend" (ClusterIP :3000)
                          /                     \
                 Pod backend-1              Pod backend-2         <- Deployment, Node.js
                          \                     /
                       Service "db" (headless :5432)
                                     |
                               Pod db-0  <-->  PVC data-db-0 (1Gi) <- StatefulSet, PostgreSQL
```

## 9. Which local Kubernetes?
| Tool | Notes |
|---|---|
| **kind** (used here) | Cluster runs inside Docker containers. Only Docker needed. Fast, great for learning/CI |
| **minikube** | Runs in a VM or Docker. Has addons (ingress, metrics-server) |
| **Docker Desktop** | One-click Kubernetes checkbox |
| **k3s** | Lightweight real cluster for small servers / Raspberry Pi |
| Managed cloud | EKS (AWS), AKS (Azure), GKE (Google) for production |
