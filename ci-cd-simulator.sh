#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "========================================================================"
echo "🎬 [PRODUCTION CI/CD SIMULATOR] KIỂM THỬ VÀ CẬP NHẬT PHIÊN BẢN MỚI K8S"
echo "========================================================================"

# STAGE 1: Code Quality & Unit Tests
echo ""
echo "─── [Giai Đoạn 1/5] Chạy Lint & Unit Tests ───"
echo ">> Kiểm tra Backend:"
cd backend && npm run lint && npm run test && cd ..
echo ">> Kiểm tra Gateway:"
cd gateway && npm run lint && npm run test && cd ..
echo "✅ Tất cả các bài Unit Tests và Linting đã PASSED!"

# STAGE 2: Versioning
NEW_VERSION="v1.0.1"
echo ""
echo "─── [Giai Đoạn 2/5] Đóng Gói Phiên Bản Mới: ${NEW_VERSION} ───"
echo ">> Building Backend image: movie-backend:${NEW_VERSION}..."
podman build -t "movie-backend:${NEW_VERSION}" -f backend/Dockerfile backend/

# STAGE 3: Import into K8s Runtime
echo ""
echo "─── [Giai Đoạn 3/5] Nạp Image vào K3s Containerd ───"
podman save "movie-backend:${NEW_VERSION}" | sudo k3s ctr -n k8s.io images import -
sudo k3s ctr -n k8s.io images tag "localhost/movie-backend:${NEW_VERSION}" "movie-backend:${NEW_VERSION}"
sudo k3s ctr -n k8s.io images tag "localhost/movie-backend:${NEW_VERSION}" "docker.io/library/movie-backend:${NEW_VERSION}"

# STAGE 4: Rolling Update (Zero-Downtime)
echo ""
echo "─── [Giai Đoạn 4/5] Kích Hoạt Rolling Update Trên Kubernetes ───"
echo ">> Cập nhật Deployment backend-service sang image version mới..."
kubectl set image deployment/backend-service backend="movie-backend:${NEW_VERSION}" -n movie-booking

echo ">> Theo dõi quá trình thay thế Pod (Rolling Update)..."
kubectl rollout status deployment/backend-service -n movie-booking --timeout=60s

echo ""
echo ">> Lịch sử các phiên bản Deployment:"
kubectl rollout history deployment/backend-service -n movie-booking

echo ""
echo "✅ Cập nhật thành công lên ${NEW_VERSION} mà không làm gián đoạn người dùng (Zero-Downtime)!"

# STAGE 5: Hướng Dẫn Rollback
echo ""
echo "========================================================================"
echo "💡 BÍ KÍP DEVOPS: NẾU PHIÊN BẢN MỚI CÓ LỖI, ROLLBACK NHƯ THẾ NÀO?"
echo "========================================================================"
echo "Chạy lệnh sau để lùi về phiên bản trước đó ngay tức khắc:"
echo "   kubectl rollout undo deployment/backend-service -n movie-booking"
echo ""
echo "Hoặc lùi về một bản cụ thể theo số Revision:"
echo "   kubectl rollout undo deployment/backend-service -n movie-booking --to-revision=1"
echo "========================================================================"
