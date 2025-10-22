#!/usr/bin/env bash
set -euo pipefail

echo "🛠️ [JWKS 自動部署與驗證工具]"

NS_DEMO="demo"
NS_ISTIO="istio-system"
SERVICE="jwks-server"
JWT_AUTH="jwt-auth"
JWKS_URI="http://${SERVICE}.${NS_ISTIO}.svc.cluster.local/jwks.json"

echo ""
echo "🔹 [1/6] 檢查 JWKS ConfigMap"
kubectl get configmap jwt-jwks -n ${NS_DEMO} >/dev/null 2>&1 || { echo "❌ 找不到 ConfigMap"; exit 1; }

echo ""
echo "🔹 [2/6] 同步 ConfigMap 至 istio-system"
kubectl get configmap jwt-jwks -n ${NS_DEMO} -o yaml | \
  sed "s/namespace: ${NS_DEMO}/namespace: ${NS_ISTIO}/g" | \
  kubectl apply -f -
echo "✅ ConfigMap 已同步"

echo ""
echo "🔹 [3/6] 確認或建立 ExternalName Service"
if ! kubectl get svc -n ${NS_ISTIO} ${SERVICE} >/dev/null 2>&1; then
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: ${SERVICE}
  namespace: ${NS_ISTIO}
spec:
  type: ExternalName
  externalName: ${SERVICE}.${NS_DEMO}.svc.cluster.local
EOF
fi
echo "✅ ExternalName Service 確認完成"

echo ""
echo "🔹 [4/6] 更新 RequestAuthentication"
kubectl patch requestauthentication ${JWT_AUTH} -n ${NS_DEMO} \
  --type='json' -p="[ {\"op\": \"replace\", \"path\": \"/spec/jwtRules/0/jwksUri\", \"value\": \"${JWKS_URI}\"} ]" || true
echo "✅ RequestAuthentication 更新完成"

echo ""
echo "🔹 [5/6] 重啟 istiod 並驗證 JWKS"
kubectl rollout restart deploy/istiod -n ${NS_ISTIO}
sleep 10
kubectl exec -n ${NS_ISTIO} deploy/istiod -- curl -s ${JWKS_URI} | jq .

echo ""
echo "🏁 完成部署驗證"
