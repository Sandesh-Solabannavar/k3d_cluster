#!/bin/bash

# Set paths
CLUSTER_CONFIG_PATH="./k3d-ha-cluster.yaml"

# Write K3d cluster config to file
cat <<'EOF' > "$CLUSTER_CONFIG_PATH"
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
EOF

# Create the cluster
k3d cluster create --config "$CLUSTER_CONFIG_PATH"

kubectl apply -f ./secrets/vault-token.yaml

kubectl apply -f https://raw.githubusercontent.com/gimlet-io/capacitor/refs/tags/capacitor-v0.4.8/deploy/k8s/rbac.yaml
kubectl apply -f https://raw.githubusercontent.com/gimlet-io/capacitor/refs/tags/capacitor-v0.4.8/deploy/k8s/manifest.yaml

echo "✅ HA K3d cluster setup complete!"
