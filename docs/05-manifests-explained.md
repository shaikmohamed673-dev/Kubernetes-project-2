# 5. Kubernetes Manifests — Every Line Explained

Every manifest has the same 4 top-level parts:
```yaml
apiVersion:   # which API group/version defines this kind
kind:         # what type of object
metadata:     # name, namespace, labels
spec:         # the DESIRED state (Secrets/ConfigMaps use data/stringData instead)
```
Apply order matters only for dependencies; files are numbered so the namespace and secret exist first.
A line with `---` separates two objects in one file.

---

## 00-namespace.yaml
```yaml
apiVersion: v1          # core API group
kind: Namespace         # a virtual cluster partition
metadata:
  name: three-tier      # all our objects use namespace: three-tier
```

## 01-secret.yaml
```yaml
kind: Secret
metadata:
  name: db-secret       # other objects refer to it by this name
  namespace: three-tier # which namespace it lives in
type: Opaque            # generic key/value secret
stringData:             # write plain text; Kubernetes stores it base64-encoded
  POSTGRES_USER: appuser
  POSTGRES_PASSWORD: change_me_strong_password
  POSTGRES_DB: appdb
```
Used by both the database (to create the user) and the backend (to connect). One source of truth.

## 02-configmap-init.yaml
```yaml
kind: ConfigMap
metadata:
  name: db-init
data:
  init.sql: |           # key = file name; "|" starts a multi-line text block
    CREATE TABLE ...
```
Mounted into the DB Pod as a file `/docker-entrypoint-initdb.d/init.sql`. The Postgres image runs it **once**, only when the data directory is empty.

---

## 03-database.yaml

### Headless Service
```yaml
kind: Service
metadata:
  name: db              # DNS name the backend uses: DB_HOST=db
  labels: {app: db}
spec:
  clusterIP: None       # headless: no virtual IP, DNS returns the Pod IP. Required for StatefulSet identity
  selector:
    app: db             # send to Pods that have label app=db
  ports:
    - name: pg
      port: 5432        # port clients connect to
      targetPort: 5432  # port on the container
```

### StatefulSet
```yaml
apiVersion: apps/v1     # Deployments/StatefulSets live in apps/v1
kind: StatefulSet       # for databases: stable name and own disk
spec:
  serviceName: db       # the headless Service that governs this set
  replicas: 1           # one DB instance (real HA needs replication tooling)
  selector:
    matchLabels:
      app: db           # which Pods belong to this StatefulSet
  template:             # the Pod blueprint
    metadata:
      labels:
        app: db         # MUST match selector above
        tier: database
    spec:
      containers:
        - name: postgres
          image: postgres:16-alpine     # same image as in Docker
          ports:
            - name: pg
              containerPort: 5432
          envFrom:
            - secretRef:
                name: db-secret         # inject ALL keys of the Secret as env vars
          env:
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata   # use a sub-folder: a fresh volume root can contain lost+found, which breaks initdb
          volumeMounts:
            - name: data                # from volumeClaimTemplates below
              mountPath: /var/lib/postgresql/data      # where Postgres stores files
            - name: initdb              # from volumes below
              mountPath: /docker-entrypoint-initdb.d   # scripts run on first start
          readinessProbe:               # "can I take traffic?"
            exec:
              command: ["sh","-c","pg_isready -U $POSTGRES_USER -d $POSTGRES_DB"]
            initialDelaySeconds: 5      # wait 5s before first check
            periodSeconds: 5            # then every 5s
          livenessProbe:                # "am I alive?" failure -> restart container
            exec: (same command)
            initialDelaySeconds: 30
            periodSeconds: 10
          resources:
            requests: {cpu: 100m, memory: 256Mi}   # guaranteed minimum (used for scheduling)
            limits:   {cpu: 500m, memory: 512Mi}   # hard maximum
      volumes:
        - name: initdb
          configMap:
            name: db-init               # mount our ConfigMap as files
  volumeClaimTemplates:                 # creates one PVC per Pod automatically (data-db-0)
    - metadata:
        name: data
      spec:
        accessModes: ["ReadWriteOnce"]  # mounted read-write by ONE node at a time
        resources:
          requests:
            storage: 1Gi                # size of the disk
```
`volumeClaimTemplates` is why the data survives Pod deletion: the PVC stays and is re-attached to the new `db-0`.

---

## 04-backend.yaml

### Deployment
```yaml
kind: Deployment
spec:
  replicas: 2                    # run 2 identical Pods (load balancing + availability)
  selector:
    matchLabels: {app: backend}  # Deployment manages Pods with this label
  template:
    metadata:
      labels: {app: backend, tier: application}
    spec:
      securityContext:
        runAsNonRoot: true       # refuse to start if the image would run as root
        runAsUser: 1000          # the "node" user in the image (numeric ID required for the check)
      initContainers:
        - name: wait-for-db
          image: busybox:1.36
          command: ["sh","-c","until nc -z db 5432; do echo waiting for db; sleep 2; done"]
          # loop until TCP port 5432 of Service "db" accepts connections. Replaces compose depends_on
      containers:
        - name: backend
          image: app-backend:1.0          # built from Dockerfile.backend
          imagePullPolicy: IfNotPresent   # use the local image (kind load) instead of pulling
          ports:
            - containerPort: 3000
          env:
            - name: DB_HOST
              value: db                   # Service name -> cluster DNS resolves it
          envFrom:
            - secretRef: {name: db-secret}   # POSTGRES_USER / PASSWORD / DB
          readinessProbe:
            httpGet: {path: /api/health, port: 3000}   # HTTP 200 = ready
            initialDelaySeconds: 5
            periodSeconds: 5
          livenessProbe:
            httpGet: {path: /api/health, port: 3000}
            initialDelaySeconds: 15
            periodSeconds: 10
          resources:
            requests: {cpu: 50m, memory: 64Mi}
            limits:   {cpu: 250m, memory: 128Mi}
          securityContext:
            allowPrivilegeEscalation: false    # process cannot gain more privileges
```

### Service
```yaml
kind: Service
spec:
  type: ClusterIP        # internal only: the internet cannot reach the backend directly
  selector: {app: backend}
  ports:
    - port: 3000         # Service port (what Nginx calls: http://backend:3000)
      targetPort: 3000   # container port
```

---

## 05-frontend.yaml
Same structure as the backend. Differences:
```yaml
image: app-frontend:1.0     # Nginx image built from Dockerfile.frontend
containerPort: 80
readinessProbe: httpGet path: /   # homepage must answer 200
---
kind: Service
spec:
  type: NodePort            # opens a port on every node to the outside
  ports:
    - port: 80              # Service port inside the cluster
      targetPort: 80        # Nginx container port
      nodePort: 30080       # external port (range 30000-32767); kind maps 8080 -> 30080
```
Nginx forwards `/api/` to `http://backend:3000`; Kubernetes DNS resolves `backend` to the backend Service, which balances across both backend Pods.

---

## optional/networkpolicy.yaml
```yaml
kind: NetworkPolicy
spec:
  podSelector: {matchLabels: {app: db}}    # this policy protects Pods labeled app=db
  policyTypes: ["Ingress"]                 # it controls INCOMING traffic
  ingress:
    - from:
        - podSelector: {matchLabels: {app: backend}}   # allow only from backend Pods
      ports:
        - port: 5432
```
Once any policy selects a Pod, all other incoming traffic to it is denied. The second policy does the same for the backend (only frontend may call it). This recreates the two-network isolation from Docker Compose.

## optional/ingress.yaml
Routes `http://3tier.local/` to Service `frontend:80` through an Ingress controller. Use it on real clusters with a domain and TLS instead of NodePort.

## optional/hpa.yaml
`scaleTargetRef` points at the backend Deployment; keeps average CPU near 70% by scaling between 2 and 5 Pods.

## kind-config.yaml
```yaml
kind: Cluster
nodes:
  - role: control-plane      # a single node that does everything (fine for learning)
    extraPortMappings:
      - containerPort: 30080 # NodePort inside the kind node container
        hostPort: 8080       # port on YOUR machine
```
Without this mapping the NodePort would only be reachable inside Docker's network.

---

## Dockerfiles
Unchanged from the Docker version. See `03-dockerfile-explained.md`. Kubernetes reads the image, not the Dockerfile, so build and load the images first.
