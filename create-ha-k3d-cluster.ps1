# Set paths
$KUBECONFIG_PATH = "$env:USERPROFILE\.kube\config"
$METALLB_CONFIG_PATH = ".\metallb-config.yaml"
$KUBEVIP_CONFIG_PATH = ".\kube-vip.yaml"
$CLUSTER_CONFIG_PATH = ".\k3d-ha-cluster.yaml"
$TRAEFIK_INGRESS = ".\traefik-ingress.yaml"

# Write K3d cluster config to file
@'
apiVersion: k3d.io/v1alpha5
kind: Simple
metadata:
  name: stg-cluster
servers: 3
agents: 2
kubeAPI:
  host: "127.0.0.1"
  hostIP: "127.0.0.1"
  hostPort: "6443"
image: rancher/k3s:v1.29.4-k3s1
options:
  k3s:
    extraArgs:
      - arg: "--disable=traefik"
        nodeFilters:
          - server:*
  kubeconfig:
    updateDefaultKubeconfig: true
    switchCurrentContext: true
network: ha-net
ports:
  - port: 8080:80
    nodeFilters:
      - loadbalancer
  - port: 8443:443
    nodeFilters:
      - loadbalancer
'@ | Set-Content -Encoding utf8 $CLUSTER_CONFIG_PATH

# Create the cluster
k3d cluster create --config $CLUSTER_CONFIG_PATH

# Write kubeconfig to default path
k3d kubeconfig get ha-cluster | Set-Content -Encoding utf8 $KUBECONFIG_PATH

# Patch kubeconfig to use 127.0.0.1
(Get-Content $KUBECONFIG_PATH) -replace "k3d-ha-cluster\.localhost", "127.0.0.1" | Set-Content -Encoding utf8 $KUBECONFIG_PATH

# Wait for cluster to be ready
Write-Host "⏳ Waiting for kube-vip and core services to stabilize..."
Start-Sleep -Seconds 15

# Deploy MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.13.10/config/manifests/metallb-native.yaml

# Wait for MetalLB pods
Write-Host "⏳ Waiting for MetalLB pods to be ready..."
kubectl wait --namespace metallb-system --for=condition=Ready pods --all --timeout=120s

# Apply MetalLB IPAddressPool config
kubectl apply -f $METALLB_CONFIG_PATH

# === Deploy Traefik ===

# Add Helm repo and update
helm repo add traefik https://traefik.github.io/charts
helm repo update

# Create namespace for Traefik
kubectl create namespace traefik

# Install Traefik with fixed LoadBalancer IP
helm upgrade --install traefik traefik/traefik `
  --namespace traefik `
  -f traefik-values.yaml

# Wait for Traefik pods
Write-Host "⏳ Waiting for Traefik pods to be ready..."
kubectl wait --namespace traefik --for=condition=Ready pods --all --timeout=120s

# Apply Traefik Ingress
kubectl apply -f $TRAEFIK_INGRESS

# Install ArgoCD
kubectl create namespace argocd
kubectl kustomize --enable-helm .\argocd | kubectl apply -f -

Write-Host "✅ HA K3d cluster setup complete!"
