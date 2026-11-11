# 4. kubectl and kind Commands — What and Why

`kubectl` is the CLI that talks to the Kubernetes API Server. Pattern: `kubectl <verb> <resource> [name] [flags]`.
Add `-n three-tier` to target our namespace (or set it as default, see section H).

## A. Cluster and context
| Command | What it does | Why |
|---|---|---|
| `kubectl version` | Client and server versions | Check install and compatibility |
| `kubectl cluster-info` | API server and DNS addresses | Confirm you are connected |
| `kubectl get nodes -o wide` | List nodes, IPs, versions | Check cluster health |
| `kubectl config get-contexts` | List clusters you can talk to | Avoid deploying to the wrong cluster |
| `kubectl config use-context kind-three-tier` | Switch cluster | Target the right one |
| `kubectl config current-context` | Show active cluster | Safety check before delete |
| `kubectl api-resources` | List all resource kinds and short names | Discover what exists |
| `kubectl explain deployment.spec.strategy` | Built-in docs for any YAML field | Learn fields without a browser |

## B. Create and update (declarative)
| Command | What | Why |
|---|---|---|
| `kubectl apply -f k8s/` | Create/update everything in the folder to match the YAML | **The main deploy command.** Safe to re-run |
| `kubectl apply -f k8s/04-backend.yaml` | Apply one file | Change one component |
| `kubectl apply -f k8s/optional/networkpolicy.yaml` | Apply optional extras | Add features |
| `kubectl diff -f k8s/` | Show what would change | Review before applying |
| `kubectl delete -f k8s/` | Delete everything defined in the files | Tear down |
| `kubectl delete namespace three-tier` | Delete namespace and everything inside | Full cleanup |
| `kubectl create secret generic db-secret --from-literal=POSTGRES_PASSWORD=x -n three-tier` | Create a secret without a YAML file | Keep real passwords out of Git |
| `kubectl create namespace dev` | Create namespace | Separate environments |

## C. Inspect
| Command | What | Why |
|---|---|---|
| `kubectl get pods -n three-tier` | List Pods and status | First thing to check |
| `kubectl get pods -n three-tier -o wide` | Adds node and Pod IP | See placement |
| `kubectl get pods -n three-tier -w` | Watch live changes | See rollout progress |
| `kubectl get all -n three-tier` | Pods, Services, Deployments, ReplicaSets, StatefulSets | Overview |
| `kubectl get svc,pvc,cm,secret -n three-tier` | Services, volume claims, configs, secrets | Check supporting objects |
| `kubectl get pods -l app=backend -n three-tier` | Filter by label | Select a group |
| `kubectl get pod <name> -o yaml` | Full live object | See what the cluster really has |
| `kubectl describe pod <name> -n three-tier` | Details and **Events** at the bottom | **Best debugging command** (pull errors, probe failures, scheduling) |
| `kubectl get events -n three-tier --sort-by=.lastTimestamp` | Recent cluster events | Find what went wrong |
| `kubectl get endpoints backend -n three-tier` | Pod IPs behind a Service | Empty = label mismatch or Pods not Ready |

Common Pod statuses:
| Status | Meaning | Look at |
|---|---|---|
| `Pending` | Not scheduled / waiting for storage | `describe pod` (resources, PVC) |
| `ContainerCreating` | Pulling image, mounting volumes | `describe pod` |
| `Running` + `0/1 READY` | Started but readiness probe failing | `logs`, probe config |
| `CrashLoopBackOff` | Container keeps crashing | `logs --previous` |
| `ImagePullBackOff` / `ErrImagePull` | Cannot pull image (wrong name/tag, not loaded into kind, no credentials) | `describe pod`, image name |
| `OOMKilled` | Exceeded memory limit | raise `limits.memory` |
| `Completed` | Finished (Jobs, init containers) | normal |

## D. Logs and access
| Command | What | Why |
|---|---|---|
| `kubectl logs deploy/backend -n three-tier` | App output | See errors |
| `kubectl logs -f <pod> -n three-tier` | Follow live | Live debugging |
| `kubectl logs <pod> --previous` | Logs of the crashed prior container | Find why it crashed |
| `kubectl logs -l app=backend --tail=50` | Logs from all matching Pods | See all replicas |
| `kubectl exec -it <pod> -n three-tier -- sh` | Shell inside a container | Inspect, test DNS (`nc -z db 5432`) |
| `kubectl exec -it db-0 -n three-tier -- psql -U appuser -d appdb` | SQL shell | Query data |
| `kubectl port-forward svc/frontend 8080:80 -n three-tier` | Tunnel a local port to a Service | Test without NodePort/Ingress |
| `kubectl port-forward pod/db-0 5432:5432 -n three-tier` | Tunnel to a Pod | Use a local DB tool |
| `kubectl cp <pod>:/path ./local -n three-tier` | Copy files | Grab logs/dumps |
| `kubectl run tmp --rm -it --image=busybox:1.36 -n three-tier -- sh` | Temporary debug Pod | Test network from inside the cluster |
| `kubectl top pods -n three-tier` | CPU/RAM usage (needs metrics-server) | Tune resources |

## E. Deployments: scale, update, rollback
| Command | What | Why |
|---|---|---|
| `kubectl scale deploy/backend --replicas=4 -n three-tier` | Change replica count | Handle more load |
| `kubectl set image deploy/backend backend=app-backend:1.1 -n three-tier` | Change image (triggers rolling update) | Release new version |
| `kubectl rollout status deploy/backend -n three-tier` | Wait for rollout to finish | Confirm success / use in scripts |
| `kubectl rollout history deploy/backend -n three-tier` | List revisions | See past versions |
| `kubectl rollout undo deploy/backend -n three-tier` | Roll back to previous version | Fast recovery |
| `kubectl rollout undo deploy/backend --to-revision=2` | Roll back to a specific revision | Pick a known-good version |
| `kubectl rollout restart deploy/backend -n three-tier` | Restart all Pods gradually | Pick up new Secret/ConfigMap or same-tag image |
| `kubectl rollout pause/resume deploy/backend` | Pause and resume rollout | Staged release |
| `kubectl autoscale deploy backend --min=2 --max=5 --cpu-percent=70` | Create an HPA | Auto scaling |

## F. Edit and delete single objects
| Command | Why |
|---|---|
| `kubectl edit deploy/backend -n three-tier` | Quick live edit (not saved in Git; prefer editing YAML and `apply`) |
| `kubectl delete pod <name> -n three-tier` | Kill one Pod; the controller creates a fresh one (**self-healing demo**) |
| `kubectl delete pvc data-db-0 -n three-tier` | Delete DB storage (**DATA LOST**) |
| `kubectl label pod <name> app=test --overwrite` | Change a label |

## G. kind (local cluster in Docker)
| Command | What / Why |
|---|---|
| `kind create cluster --name three-tier --config kind-config.yaml` | Create cluster with the port mapping 8080 -> 30080 |
| `kind get clusters` | List clusters |
| `kind load docker-image app-backend:1.0 --name three-tier` | Copy a locally built image into the cluster nodes (kind cannot see your local Docker images otherwise) |
| `kind delete cluster --name three-tier` | Remove the whole cluster |
| `docker ps` | The kind "node" is just a Docker container |

## H. Productivity
| Command | Why |
|---|---|
| `kubectl config set-context --current --namespace=three-tier` | Stop typing `-n three-tier` |
| `alias k=kubectl` | Shorter typing |
| `kubectl get po,svc,deploy,sts,pvc,cm` | Short names: po=pods, svc=services, deploy=deployments, sts=statefulsets, pvc=persistentvolumeclaims, cm=configmaps, ns=namespaces |
| `kubectl get pods -o json \| jq ...` | Script with JSON output |
| `kubectl get pods -o jsonpath='{.items[*].metadata.name}'` | Extract fields |
| `kubectl apply --dry-run=client -f k8s/` | Validate YAML without applying |

## I. Debug flow (memorize this)
1. `kubectl get pods -n three-tier` -> what is the status?
2. `kubectl describe pod <pod> -n three-tier` -> read **Events**.
3. `kubectl logs <pod> -n three-tier` (add `--previous` if it restarted).
4. `kubectl get endpoints <svc> -n three-tier` -> does the Service have Pods?
5. `kubectl exec -it <pod> -- sh` -> test DNS and connectivity from inside.
6. Fix the YAML -> `kubectl apply -f k8s/` -> `kubectl rollout status ...`

## J. Docker command <-> kubectl command
| Docker | Kubernetes |
|---|---|
| `docker ps` | `kubectl get pods` |
| `docker logs -f web` | `kubectl logs -f <pod>` |
| `docker exec -it web sh` | `kubectl exec -it <pod> -- sh` |
| `docker inspect web` | `kubectl describe pod <pod>` |
| `docker compose up -d` | `kubectl apply -f k8s/` |
| `docker compose down` | `kubectl delete -f k8s/` |
| `docker compose up -d --scale backend=3` | `kubectl scale deploy/backend --replicas=3` |
| `docker stats` | `kubectl top pods` |
| `docker run -p 8080:80` | `kubectl port-forward` / Service |
| `docker compose restart` | `kubectl rollout restart` |
