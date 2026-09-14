# Expenses Tracker — GitOps with Argo CD

A complete GitOps implementation for the [Expenses Tracker WebApp](https://github.com/sudarshanvashisht/Expenses-Tracker-WebApp) using **Kubernetes**, **Kustomize**, **Argo CD**, and **GitHub Actions**.

## Architecture

```
Developer pushes code
        │
        ▼
┌──────────────────────┐
│  GitHub Actions (CI)  │
│                      │
│  • Maven test        │
│  • Docker build      │
│  • Trivy scan        │
│  • Push to Docker Hub│
│  • Update GitOps tag │
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐         ┌──────────────────────────┐
│  GitOps Repo (Git)   │ ◄────── │  Argo CD (watches Git)   │
│                      │         │                          │
│  Kustomize manifests │         │  • Detects drift         │
│  Desired state       │         │  • Auto-sync             │
│  Image tags          │         │  • Self-heal             │
└──────────────────────┘         └────────────┬─────────────┘
                                              │
                                              ▼
                                 ┌──────────────────────────┐
                                 │  Kubernetes Cluster      │
                                 │                          │
                                 │  ┌─────────────────────┐ │
                                 │  │ Spring Boot (2 pods) │ │
                                 │  │    Deployment        │ │
                                 │  └─────────┬───────────┘ │
                                 │            │              │
                                 │  ┌─────────▼───────────┐ │
                                 │  │ MySQL (StatefulSet)  │ │
                                 │  │    + PVC             │ │
                                 │  └─────────────────────┘ │
                                 └──────────────────────────┘
```

## Repository Structure

```
Expenses-Tracker-GitOps/
│
├── base/                          # Base Kubernetes manifests
│   ├── kustomization.yaml         # Kustomize config + image tag
│   ├── namespace.yaml             # expenses namespace
│   ├── mysql-secret.yaml          # Database credentials (K8s Secret)
│   ├── mysql-service.yaml         # MySQL ClusterIP service
│   ├── mysql-statefulset.yaml     # MySQL StatefulSet + PVC
│   ├── app-deployment.yaml        # Spring Boot Deployment
│   └── app-service.yaml           # Spring Boot Service
│
├── overlays/
│   └── kind/                      # Kind cluster overlay
│       └── kustomization.yaml     # NodePort patch for local access
│
├── argocd/
│   └── application.yaml           # Argo CD Application manifest
│
└── ci-workflow-for-app-repo/
    └── ci.yml                     # GitHub Actions CI (copy to app repo)
```

## Quick Start — Deploy to Kind Cluster

### Prerequisites

- [kind](https://kind.sigs.k8s.io/) cluster running (`kind-tws-cluster`)
- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [kustomize](https://kubectl.docs.kubernetes.io/installation/kustomize/) (or use `kubectl -k`)

### Step 1 — Install Argo CD

```bash
kubectl create namespace argocd

kubectl apply -n argocd --server-side --force-conflicts \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for all pods to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/part-of=argocd -n argocd --timeout=300s
```

### Step 2 — Access Argo CD UI

```bash
# Port-forward (run in background)
kubectl port-forward svc/argocd-server -n argocd 8080:443 &

# Get the admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d; echo

# Open https://localhost:8080
# Username: admin
# Password: <from above command>
```

### Step 3 — Register the Application with Argo CD

```bash
kubectl apply -f argocd/application.yaml
```

That's it! Argo CD will now:
1. Clone this GitOps repository
2. Build the Kustomize overlay for `kind`
3. Deploy all resources to the `expenses` namespace
4. Continuously watch for changes

### Step 4 — Verify Deployment

```bash
# Check pods
kubectl get pods -n expenses

# Check services
kubectl get svc -n expenses

# Check StatefulSet
kubectl get statefulset -n expenses

# Check PVCs
kubectl get pvc -n expenses

# Access the application
kubectl port-forward svc/expenses-tracker -n expenses 9090:80
# Open http://localhost:9090
```

---

## CI Setup — GitHub Actions (Application Repo)

### 1. Copy the CI workflow

Copy `ci-workflow-for-app-repo/ci.yml` to the **application repository**:

```bash
# In the Expenses-Tracker-WebApp repo
mkdir -p .github/workflows
cp /path/to/Expenses-Tracker-GitOps/ci-workflow-for-app-repo/ci.yml .github/workflows/ci.yml
```

### 2. Configure GitHub Secrets

In the **Expenses-Tracker-WebApp** repo → Settings → Secrets and variables → Actions:

| Secret Name | Description |
|-------------|-------------|
| `DOCKERHUB_USERNAME` | Your Docker Hub username (e.g., `sudarshan0907`) |
| `DOCKERHUB_TOKEN` | Docker Hub access token ([create here](https://hub.docker.com/settings/security)) |
| `GIT_TOKEN` | GitHub Personal Access Token with `repo` scope ([create here](https://github.com/settings/tokens)) |

### 3. CI Pipeline Flow

```
Push to main → Maven test → Docker build → Trivy scan → Docker Hub push → Update GitOps image tag
```

The last step commits the new image tag to this GitOps repo, which triggers Argo CD to deploy.

---

## GitOps Demo — Proving It Works

### Demo 1: Scaling via Git (Desired State)

```bash
# Current state: 2 replicas
kubectl get pods -n expenses -l app.kubernetes.io/name=expenses-tracker

# Edit base/app-deployment.yaml: change replicas: 2 → replicas: 3
# Commit and push to this repo

# Watch Argo CD detect the change and sync
kubectl get pods -n expenses -l app.kubernetes.io/name=expenses-tracker -w
# → 3 pods will appear
```

### Demo 2: Self-Healing (Drift Detection)

```bash
# Git says replicas: 3
# Manually scale down
kubectl scale deployment expenses-tracker -n expenses --replicas=1

# Watch Argo CD self-heal — it detects drift and restores to 3
kubectl get pods -n expenses -l app.kubernetes.io/name=expenses-tracker -w
# → Back to 3 pods within seconds
```

### Demo 3: Full CI/CD Pipeline

```bash
# 1. Make a code change in Expenses-Tracker-WebApp
# 2. Push to main
# 3. GitHub Actions runs CI pipeline
# 4. New Docker image pushed: sudarshan0907/expenses-tracker:<sha>
# 5. GitOps repo updated with new tag
# 6. Argo CD detects change → syncs → rolling update
# 7. Zero-downtime deployment!
```

### Demo 4: Argo CD Dashboard

Check the Argo CD UI at `https://localhost:8080`:

- **Synced + Healthy** = Git and cluster match ✅
- **OutOfSync** = Someone changed Git or cluster ⚠️
- **Degraded** = Pods are unhealthy ❌

---

## Kubernetes Resources Deployed

| Resource | Name | Type | Details |
|----------|------|------|---------|
| Namespace | `expenses` | Namespace | Isolates all resources |
| Deployment | `expenses-tracker` | Deployment | 2 replicas, rolling updates |
| Service | `expenses-tracker` | NodePort (kind) | Port 80 → 8080 |
| StatefulSet | `mysql` | StatefulSet | 1 replica, persistent storage |
| Service | `mysql` | ClusterIP | Internal-only, port 3306 |
| PVC | `mysql-data-mysql-0` | PVC | 1Gi persistent volume |
| Secret | `mysql-secret` | Opaque | DB credentials |

---

## Security Considerations

| Practice | Implementation |
|----------|---------------|
| No hardcoded passwords | Kubernetes Secrets (base64-encoded) |
| Password rotated | `Test@123` → new password in K8s Secret |
| MySQL not exposed | ClusterIP service, no external access |
| Non-root containers | Recommended (add to Dockerfile) |
| Image scanning | Trivy in CI pipeline |
| Immutable tags | Git SHA-based tags (`a82f31c`) |

> **For production**: Use [Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets) or [External Secrets Operator](https://external-secrets.io/) instead of plain K8s Secrets.

---

## Key GitOps Concepts Demonstrated

| Concept | How It's Shown |
|---------|----------------|
| **Git as single source of truth** | All K8s manifests live here |
| **Declarative desired state** | Kustomize manifests define what should exist |
| **Automated sync** | Argo CD watches Git and applies changes |
| **Self-healing** | `selfHeal: true` reverts manual cluster changes |
| **Immutable deployments** | Git SHA-tagged Docker images |
| **Separation of concerns** | CI (GitHub Actions) ≠ CD (Argo CD) |
| **Drift detection** | Argo CD shows OutOfSync when cluster ≠ Git |

---

## Future Enhancements

- [ ] Sealed Secrets for production secret management
- [ ] Ingress Controller for proper routing
- [ ] Horizontal Pod Autoscaler
- [ ] Network Policies
- [ ] Prometheus/Grafana monitoring
- [ ] Multiple environments (dev/staging/prod overlays)
- [ ] Spring Boot Actuator for HTTP health probes
