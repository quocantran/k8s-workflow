#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "============================================================"
echo "🚀 [K8s CI/CD Pipeline] Build & Deploy Movie Booking"
echo "============================================================"

TAG="v1.0.0"

# 1. Build Frontend Image
echo "==> [1/3] Building movie-frontend:$TAG..."
podman build -t "movie-frontend:$TAG" -f frontend/Dockerfile frontend/

# 2. Build Backend Image
echo "==> [2/3] Building movie-backend:$TAG..."
podman build -t "movie-backend:$TAG" -f backend/Dockerfile backend/

# 3. Build Gateway Image
echo "==> [3/3] Building movie-gateway:$TAG..."
podman build -t "movie-gateway:$TAG" -f gateway/Dockerfile gateway/

# 4. Import Images trực tiếp vào containerd của K3s (Không cần push lên mạng)
echo "==> [4/4] Importing images vào K3s containerd runtime..."
podman save "movie-frontend:$TAG" | sudo k3s ctr images import -
podman save "movie-backend:$TAG"  | sudo k3s ctr images import -
podman save "movie-gateway:$TAG"  | sudo k3s ctr images import -

echo "==> Đã import thành công 3 images vào K3s!"
sudo k3s ctr images list | grep movie-

# 5. Apply Kubernetes Manifests
echo "==> [5/5] Deploying lên Kubernetes..."
kubectl apply -f k8s/01-namespace.yaml
kubectl apply -f k8s/02-external-mysql.yaml
kubectl apply -f k8s/03-configmap.yaml
kubectl apply -f k8s/03-secret.yaml 2>/dev/null || kubectl apply -f k8s/03-secret.yaml.example
kubectl apply -f k8s/04-redis.yaml
kubectl apply -f k8s/05-backend.yaml
kubectl apply -f k8s/06-gateway.yaml
kubectl apply -f k8s/07-frontend.yaml
kubectl apply -f k8s/08-ingress.yaml
kubectl apply -f k8s/09-hpa.yaml

echo "============================================================"
echo "✅ HOÀN TẤT TRIỂN KHAI!"
echo "Kiểm tra Pods:   kubectl get pods -n movie-booking"
echo "Kiểm tra Ingress: kubectl get ingress -n movie-booking"
echo "Truy cập Web:    http://127.0.0.1:30080/"
echo "============================================================"
