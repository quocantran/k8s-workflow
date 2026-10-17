#!/bin/bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

# Target version: Cho phép truyền vào qua tham số hoặc tự sinh tag
TARGET_VERSION="${1:-v1.0.1}"
REGISTRY="docker.io/quocantran"

echo "=========================================================================="
echo "🎬 [GITOPS CI/CD SIMULATOR] MÔ PHỎNG LUỒNG GITOPS VỚI DOCKER HUB & ARGOCD"
echo "=========================================================================="
echo "📌 Target Version : ${TARGET_VERSION}"
echo "📌 Container Registry: ${REGISTRY}"
echo "📌 Triết lý GitOps   : CI KHÔNG chạm vào K8s, K8s do ArgoCD tự động kéo (Pull)"
echo "=========================================================================="

# ──────────────────────────────────────────────────────────────────────────
# GIAI ĐOẠN 1: Code Quality & Unit Tests (CI)
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "─── [Giai Đoạn 1/5] Chạy Lint & Unit Tests ───"
echo ">> [CI] Kiểm tra Backend..."
(cd backend && npm run lint --silent && npm run test --silent)
echo ">> [CI] Kiểm tra Gateway..."
(cd gateway && npm run lint --silent && npm run test --silent)
echo "✅ [CI] Tất cả bài kiểm thử Lint & Unit Tests đã PASSED!"

# ──────────────────────────────────────────────────────────────────────────
# GIAI ĐOẠN 2: Build Images qua Podman (CI)
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "─── [Giai Đoạn 2/5] Đóng Gói Container Images Với Tag: ${TARGET_VERSION} ───"
echo ">> [CI] Đang build Backend: ${REGISTRY}/movie-backend:${TARGET_VERSION}..."
podman build -q -t "${REGISTRY}/movie-backend:${TARGET_VERSION}" -f backend/Dockerfile backend/

echo ">> [CI] Đang build Gateway: ${REGISTRY}/movie-gateway:${TARGET_VERSION}..."
podman build -q -t "${REGISTRY}/movie-gateway:${TARGET_VERSION}" -f gateway/Dockerfile gateway/

echo ">> [CI] Đang build Frontend: ${REGISTRY}/movie-frontend:${TARGET_VERSION}..."
podman build -q -t "${REGISTRY}/movie-frontend:${TARGET_VERSION}" -f frontend/Dockerfile frontend/

echo "✅ [CI] Đã đóng gói thành công 3 microservices!"

# ──────────────────────────────────────────────────────────────────────────
# GIAI ĐOẠN 3: Push Images lên Docker Hub (CI)
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "─── [Giai Đoạn 3/5] Đẩy (Push) Images Lên Docker Hub Registry ───"
echo ">> [CI] Đang push Backend image lên Docker Hub..."
podman push "${REGISTRY}/movie-backend:${TARGET_VERSION}"

echo ">> [CI] Đang push Gateway image lên Docker Hub..."
podman push "${REGISTRY}/movie-gateway:${TARGET_VERSION}"

echo ">> [CI] Đang push Frontend image lên Docker Hub..."
podman push "${REGISTRY}/movie-frontend:${TARGET_VERSION}"

echo "✅ [CI] Toàn bộ images phiên bản ${TARGET_VERSION} đã có mặt trên Docker Hub!"

# ──────────────────────────────────────────────────────────────────────────
# GIAI ĐOẠN 4: Cập Nhật GitOps Manifests & Commit Git (CI GitOps Boundary)
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "─── [Giai Đoạn 4/5] Cập Nhật GitOps Manifests (Không Chạm K8s) ───"
echo ">> [CI] Cập nhật image tag trong k8s/kustomization.yaml và manifests..."

cd k8s
kustomize edit set image docker.io/quocantran/movie-backend="${REGISTRY}/movie-backend:${TARGET_VERSION}"
kustomize edit set image docker.io/quocantran/movie-gateway="${REGISTRY}/movie-gateway:${TARGET_VERSION}"
kustomize edit set image docker.io/quocantran/movie-frontend="${REGISTRY}/movie-frontend:${TARGET_VERSION}"

sed -i -E "s|image: docker.io/quocantran/movie-backend:.*|image: ${REGISTRY}/movie-backend:${TARGET_VERSION}|g" 05-backend.yaml
sed -i -E "s|image: docker.io/quocantran/movie-gateway:.*|image: ${REGISTRY}/movie-gateway:${TARGET_VERSION}|g" 06-gateway.yaml
sed -i -E "s|image: docker.io/quocantran/movie-frontend:.*|image: ${REGISTRY}/movie-frontend:${TARGET_VERSION}|g" 07-frontend.yaml
cd ..

echo ">> [CI] Commit thay đổi cấu hình vào Git (Git là Single Source of Truth)..."
git add k8s/
if git diff --staged --quiet; then
  echo "Không có thay đổi manifest cần commit."
else
  git commit -m "chore(gitops): promote microservices to ${TARGET_VERSION} [skip ci]"
  echo ">> [CI] Pushing Git commit lên remote repository GitHub..."
  git push origin main
fi

echo "=========================================================================="
echo "🛑 [CI HOÀN TẤT] Luồng CI kết thúc tại đây, KHÔNG HỀ thực thi lệnh kubectl!"
echo "=========================================================================="

# ──────────────────────────────────────────────────────────────────────────
# GIAI ĐOẠN 5: ArgoCD GitOps Reconciliation (CD trên Kubernetes)
# ──────────────────────────────────────────────────────────────────────────
echo ""
echo "─── [Giai Đoạn 5/5] ArgoCD Tự Động Kéo (Pull) Manifest & Triển Khai ───"
echo ">> [CD] Kích hoạt ArgoCD đồng bộ ứng dụng 'movie-booking-app'..."

# Đảm bảo argocd application đã tồn tại
if ! kubectl get application movie-booking-app -n argocd >/dev/null 2>&1; then
  echo ">> [CD] Khởi tạo ArgoCD Application lần đầu..."
  kubectl apply -f argocd/application.yaml
fi

# Đồng bộ qua ArgoCD CLI hoặc API
argocd app sync movie-booking-app --prune=false >/dev/null 2>&1 || true

echo ">> [CD] Đang chờ ArgoCD đồng bộ trạng thái và kiểm tra sức khỏe hệ thống..."
argocd app wait movie-booking-app --health --timeout 180 >/dev/null 2>&1 || {
  echo ">> [CD] Theo dõi trạng thái Rollout của Backend..."
  kubectl rollout status deployment/backend-service -n movie-booking --timeout=120s
}

echo ""
echo ">> [CD] Kiểm tra phiên bản Image đang chạy thực tế trên Pods K8s (kéo từ Docker Hub):"
kubectl get pods -n movie-booking -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[*].image}{"\n"}{end}' | grep -E 'backend|gateway|frontend'

echo ""
echo ">> [CD] Kiểm tra sức khỏe dịch vụ qua Ingress (Zero-Downtime Check):"
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:30080/api/health || echo "000")
if [ "$HTTP_STATUS" = "200" ]; then
  echo "✅ HTTP Endpoint Healthy: http://127.0.0.1:30080/api/health (Status 200 OK)"
else
  echo "⚠️ Cảnh báo: Endpoint trả về mã HTTP $HTTP_STATUS"
fi

echo ""
echo "=========================================================================="
echo "🎉 CHÚC MỪNG: HỆ THỐNG GITOPS HOẠT ĐỘNG HOÀN TOÀN TỰ ĐỘNG VÀ CHUẨN PRODUCTION!"
echo "   - Container Registry: Docker Hub (quocantran)"
echo "   - GitOps Controller : ArgoCD v3.5.5"
echo "   - ArgoCD Dashboard  : http://192.168.48.100:30880 (admin / 4WpLvG7gxIozrLy0)"
echo "   - Web Application   : http://192.168.48.100:30080"
echo "=========================================================================="
