#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

TAG="${1:-v1.0.0}"
REGISTRY="docker.io/quocantran"

echo "============================================================"
echo "🚀 [GitOps Build & Push] Movie Booking Microservices"
echo "============================================================"
echo "Version: $TAG | Registry: $REGISTRY"
echo "============================================================"

# 1. Build Container Images via Podman
echo "==> [1/3] Building Backend image: ${REGISTRY}/movie-backend:$TAG..."
podman build -t "${REGISTRY}/movie-backend:$TAG" -f backend/Dockerfile backend/

echo "==> [2/3] Building Gateway image: ${REGISTRY}/movie-gateway:$TAG..."
podman build -t "${REGISTRY}/movie-gateway:$TAG" -f gateway/Dockerfile gateway/

echo "==> [3/3] Building Frontend image: ${REGISTRY}/movie-frontend:$TAG..."
podman build -t "${REGISTRY}/movie-frontend:$TAG" -f frontend/Dockerfile frontend/

# 2. Push Images to Docker Hub
echo "==> [4/5] Pushing images lên Docker Hub (${REGISTRY})..."
podman push "${REGISTRY}/movie-backend:$TAG"
podman push "${REGISTRY}/movie-gateway:$TAG"
podman push "${REGISTRY}/movie-frontend:$TAG"

# 3. Synchronize with ArgoCD GitOps
echo "==> [5/5] Kích hoạt ArgoCD GitOps Application..."
if [ -f "../k8s-gitops/argocd/application-production.yaml" ]; then
  kubectl apply -f ../k8s-gitops/argocd/application-production.yaml
fi

echo "============================================================"
echo "✅ HOÀN TẤT ĐẨY DOCKER HUB VÀ KHỞI TẠO ARGOCD GITOPS!"
echo "Kiểm tra ArgoCD: argocd app get movie-booking-production"
echo "Kiểm tra Pods:   kubectl get pods -n movie-booking"
echo "Truy cập Web:    http://127.0.0.1:30080/"
echo "Dashboard Argo:  http://192.168.48.100:30880/"
echo "============================================================"
