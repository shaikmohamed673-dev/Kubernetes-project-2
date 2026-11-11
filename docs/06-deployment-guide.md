# 6. Deployment Guide (Kubernetes)

## A. Tools to install
| Tool | Purpose | Install |
|---|---|---|
| Docker | builds images; kind runs inside it | docker.com / `curl -fsSL https://get.docker.com \| sh` |
| kubectl | talks to the cluster | kubernetes.io/docs/tasks/tools |
| kind | local cluster in Docker | kind.sigs.k8s.io (`brew install kind`, or download the binary) |

Check: `docker version && kubectl version --client && kind version`

## B. Local deploy (one command)
```bash
./deploy-k8s.sh
```
What it does, step by step (you can run each yourself):
```bash
kind create cluster --name three-tier --config kind-config.yaml     # 1 cluster
docker build -f Dockerfile.backend  -t app-backend:1.0  .          # 2 build images
docker build -f Dockerfile.frontend -t app-frontend:1.0 .
kind load docker-image app-backend:1.0 app-frontend:1.0 --name three-tier   # 3 copy images into cluster
kubectl apply -f k8s/                                               # 4 create all objects
kubectl -n three-tier rollout status statefulset/db                 # 5 wait until ready
kubectl -n three-tier rollout status deploy/backend
kubectl -n three-tier rollout status deploy/frontend
```
Open http://localhost:8080

## C. Verify
```bash
kubectl get all -n three-tier                       # everything Running / READY
kubectl get pvc -n three-tier                       # data-db-0 is Bound
kubectl exec -it db-0 -n three-tier -- psql -U appuser -d appdb -c "SELECT * FROM messages;"
curl http://localhost:8080/api/health               # {"status":"ok"} via frontend -> backend
```

## D. Try the self-healing and scaling
```bash
kubectl get pods -n three-tier -w                   # terminal 1: watch
kubectl delete pod -l app=backend -n three-tier     # terminal 2: kill backend Pods -> new ones appear
kubectl scale deploy/frontend --replicas=4 -n three-tier
kubectl delete pod db-0 -n three-tier               # DB Pod is recreated, SAME data (PVC kept)
```

## E. Release a new version (rolling update)
```bash
docker build -f Dockerfile.backend -t app-backend:1.1 .
kind load docker-image app-backend:1.1 --name three-tier
kubectl set image deploy/backend backend=app-backend:1.1 -n three-tier
kubectl rollout status deploy/backend -n three-tier
kubectl rollout undo deploy/backend -n three-tier      # if it is broken
```
Always use a **new tag** (1.1, 1.2). Re-using `1.0` with `IfNotPresent` will not update running Pods.
After editing the YAML (e.g. replicas), just run `kubectl apply -f k8s/` again.

## F. Change the password (Secret)
```bash
kubectl create secret generic db-secret -n three-tier \
  --from-literal=POSTGRES_USER=appuser \
  --from-literal=POSTGRES_PASSWORD='N3w-Str0ng-Pass' \
  --from-literal=POSTGRES_DB=appdb --dry-run=client -o yaml | kubectl apply -f -
kubectl rollout restart deploy/backend -n three-tier
```
Postgres only reads the password on FIRST initialization. For an existing DB also run `ALTER USER appuser PASSWORD '...'` or delete the PVC (data loss).

## G. Clean up
```bash
./cleanup-k8s.sh             # delete the app (namespace)
./cleanup-k8s.sh --cluster   # delete the whole kind cluster
```
Deleting the namespace also deletes the PVC, so the database data is gone.

## H. Alternatives to kind
**minikube**
```bash
minikube start --driver=docker
eval $(minikube docker-env)                 # build straight into minikube's Docker
docker build -f Dockerfile.backend -t app-backend:1.0 .
docker build -f Dockerfile.frontend -t app-frontend:1.0 .
kubectl apply -f k8s/
minikube service frontend -n three-tier --url
```
**Docker Desktop**: enable Kubernetes in settings, build the images normally (they are visible to the cluster), `kubectl apply -f k8s/`, open `http://localhost:30080`.

## I. Deploy to a real cluster (cloud or server)
1. **Push images to a registry**
```bash
docker login
docker build -f Dockerfile.backend  -t <user>/3tier-backend:1.0  .
docker build -f Dockerfile.frontend -t <user>/3tier-frontend:1.0 .
docker push <user>/3tier-backend:1.0
docker push <user>/3tier-frontend:1.0
```
2. In `04-backend.yaml` and `05-frontend.yaml` change `image:` to `<user>/3tier-...:1.0` and `imagePullPolicy: IfNotPresent` (fine) — private registry? create a pull secret:
```bash
kubectl create secret docker-registry regcred -n three-tier \
  --docker-username=<user> --docker-password=<token> --docker-server=https://index.docker.io/v1/
```
and add `imagePullSecrets: [{name: regcred}]` under the Pod `spec`.
3. Change the frontend Service to `type: LoadBalancer` (cloud) or use `optional/ingress.yaml` with a domain and TLS (cert-manager).
4. Replace the placeholder Secret with a real one (section F) and do not commit it.
5. `kubectl config use-context <cloud-cluster>` then `kubectl apply -f k8s/`.

## J. Backup and restore the database
```bash
kubectl exec -n three-tier db-0 -- sh -c 'pg_dump -U $POSTGRES_USER $POSTGRES_DB' > backup.sql
cat backup.sql | kubectl exec -i -n three-tier db-0 -- sh -c 'psql -U $POSTGRES_USER -d $POSTGRES_DB'
```

## K. Troubleshooting
| Symptom | Cause / fix |
|---|---|
| `ErrImagePull` / `ImagePullBackOff` | Image not loaded into kind (`kind load docker-image ...`) or wrong name/tag |
| Backend stuck in `Init:0/1` | DB not ready; `kubectl logs <backend-pod> -c wait-for-db`, then check `db-0` |
| `db-0` Pending | PVC not Bound; `kubectl describe pvc data-db-0 -n three-tier` (no StorageClass?) |
| Pod `CrashLoopBackOff` | `kubectl logs <pod> --previous` |
| Page loads, API returns 502/504 | `kubectl get endpoints backend -n three-tier` empty = Pods not Ready or label mismatch |
| localhost:8080 refused | Cluster created without `kind-config.yaml` port mapping; delete and recreate cluster, or use `kubectl port-forward svc/frontend 8080:80 -n three-tier` |
| `exec format error` | Image built for a different CPU architecture (e.g. built on Apple Silicon, running on amd64) |
| Changed Secret, app unchanged | Env vars are read at start: `kubectl rollout restart deploy/backend -n three-tier` |

## L. Production checklist
- [ ] Images pushed to a registry with fixed version tags (never `latest`)
- [ ] Real secrets via Sealed Secrets / External Secrets / cloud vault, not in Git
- [ ] Ingress + TLS, frontend Service as ClusterIP
- [ ] NetworkPolicies applied on a CNI that enforces them
- [ ] Resource requests/limits tuned with `kubectl top`
- [ ] HPA + metrics-server for the backend
- [ ] Managed database or an operator (CloudNativePG, Zalando) instead of a single-Pod StatefulSet
- [ ] Regular DB backups tested by restoring
- [ ] Separate namespaces/clusters for dev, staging, prod
- [ ] Monitoring and logs (Prometheus, Grafana, Loki)
- [ ] RBAC with least privilege; Pod Security standards enabled
