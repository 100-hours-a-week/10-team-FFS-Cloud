# v3 인프라 구축 작업 일지

> 트러블슈팅 Part 1 문서 작성 이후 수행한 작업 기록

---

## Phase 1 — K8s 클러스터 기반 구성

1. **kubeadm으로 K8s 클러스터 설치** (master 1 + worker 2)
2. **Flannel CNI 설치** — Pod 간 네트워크 오버레이
3. **nginx-ingress Controller 설치** (NodePort 방식: HTTP 32496, HTTPS 32495)
4. **Bastion nginx 리버스 프록시 구성** — 외부 트래픽 → K8s NodePort
5. **cert-manager 설치 + ClusterIssuer(letsencrypt-prod) 생성**

---

## Phase 2 — AWS 인프라 구성

6. **Route53 호스팅 존 생성** (v3.klosetlab.site)
   - 신규 AWS 계정에 서브도메인 호스팅 존 생성
   - 기존 계정 Route53에 NS 위임 레코드 추가 (이슈: 레코드 이름 오타 → 수정)
   - A 레코드: v3.klosetlab.site → 3.38.20.22 (바스티온)
7. **ECR 레포지토리 생성** 3개 (module-api, module-chat, fastapi)
8. **IAM 구성**
   - K8s 노드 IAM Role: ECR Pull 권한
   - GitHub Actions IAM User: ECR Push 권한 (최소 권한 원칙)
9. **RDS MySQL 8.0 생성** (Multi-AZ 서브넷 그룹 이슈 해결)
10. **보안 그룹 설정** — 워커 노드 → Redis/MongoDB/Kafka/Qdrant 인바운드 오픈

---

## Phase 3 — K8s 매니페스트 작성 및 배포

11. **K8s 네임스페이스 생성** (klosetlab)
12. **K8s Secret 생성** 3개 (module-api 26개, module-chat 18개, fastapi 42개 환경변수)
13. **Deployment YAML 작성** — 각 서비스별
    - imagePullSecrets 설정
    - envFrom으로 Secret 주입
    - Liveness/Readiness Probe 설정
    - Resources Requests/Limits 설정
14. **Service YAML 작성** — ClusterIP 방식
15. **Ingress YAML 작성** — 경로 기반 라우팅
    - /api → module-api
    - /ws  → module-chat (WebSocket 타임아웃 설정)
    - /ai  → fastapi (rewrite-target으로 prefix 제거)
    - cert-manager TLS 어노테이션
16. **ECR imagePullSecret 생성** + **ECR 토큰 갱신 CronJob 배포**

---

## Phase 4 — ArgoCD GitOps 구성

17. **ArgoCD 설치** (argocd 네임스페이스)
18. **ArgoCD Application 3개 등록**
    - source: infra repo v3/k8s/{service}/
    - destination: klosetlab 네임스페이스
    - syncPolicy: automated (prune + selfHeal)
19. **infra repo에 매니페스트 push** — ArgoCD 최초 sync 트리거

---

## Phase 5 — GitHub Actions CI/CD 구성

20. **GitHub Actions 워크플로우 작성** 3개 (BE module-api, BE module-chat, AI fastapi)
    - 빌드 → ECR push → infra repo 이미지 태그 업데이트
    - GitHub Secrets 등록 (V3_ prefix)
21. **FE 워크플로우 작성** — S3 sync + CloudFront 무효화
22. **모든 레포에 워크플로우 파일 push**

---

## Phase 6 — 서비스 기동 및 트러블슈팅

23. **ECR ImagePullBackOff 해결** — containerd IAM Role 미지원 → imagePullSecret 방식
24. **Route53 NS 오타 수정** — cert-manager HTTP01 챌린지 DNS 조회 실패
25. **nginx configuration-snippet 제거** — WebSocket은 nginx-ingress 자동 처리
26. **DB 마이그레이션** — v2 RDS에서 v3 RDS로 Flyway 스키마 이전 (mysqldump)
27. **CORS 수정** — Spring Boot 허용 Origin에 v3 도메인 추가 (개발자가 직접 수정)
28. **Kafka 인스턴스 구성** — Docker Compose (apache/kafka:latest, KRaft 모드)
    - Topic 생성: ai.clothes.analyze.request (p1), ai.clothes.analyze.result (p3)
29. **ECR CronJob 이미지 교체** — amazon/aws-cli → alpine/k8s (kubectl 포함)
30. **module-api OOM 해결** — JAVA_TOOL_OPTIONS으로 JVM 힙 명시 설정
31. **바스티온 SG 80/443 오픈** — 인터넷 → 바스티온 HTTP/HTTPS 허용
32. **ClusterIssuer ingressTemplate 추가** — ACME 챌린지 ssl-redirect 비활성화
33. **바스티온 nginx HTTPS 설정** — libnginx-mod-stream 설치, 443 TCP 프록시 추가
34. **FastAPI Ingress rewrite 추가** — /ai prefix 제거해 FastAPI 앱에 전달

---

## Phase 7 — 트러블슈팅 Part 2 (서비스 안정화)

35. **module-api CrashLoopBackOff 해결** — Probe timeoutSeconds 1→10, initialDelaySeconds 60→90
    - 원인: `/actuator/health` 첫 응답 4.6초 소요, 기본 timeoutSeconds=1로 probe 실패
    - `/actuator/health/liveness` 시도 → Spring Security CustomAuthenticationEntryPoint가 401 반환
    - 최종 해결: `/actuator/health` + timeoutSeconds: 10

36. **Kakao OAuth 404 해결** — Ingress `/oauth` 경로 누락
    - 원인: Ingress에 `/api` 경로만 있고 `/oauth` 없음 → nginx 404
    - 수정: Ingress에 `/oauth` 경로 추가 + KAKAO_REDIRECT_URI Secret 수정
      - `https://v3.klosetlab.site/oauth/kakao/callback`

37. **ECR CronJob Pod 누적 해결** — backoffLimit 기본값 6으로 실패 시 Pod 7개 생성
    - 수정: `jobTemplate.spec.backoffLimit: 0` 추가

38. **Calico IPIP 미완성 해결** — TCP 5473(Typha) SG 규칙 누락
    - 원인: K8s 노드가 별도 AWS 계정(862012315401)에 있어 SG 직접 수정 필요
    - klosetlab-master-sg, klosetlab-worker-sg 양쪽에 TCP 5473 인바운드 추가

39. **module-chat CrashLoopBackOff 해결** — JVM 기동 92초인데 initialDelaySeconds 60초
    - 수정: initialDelaySeconds 60→120, timeoutSeconds 1→10

---

## Phase 8 — Calico NetworkPolicy 설계

40. **Calico NetworkPolicy 매니페스트 작성**
    - Default Deny Ingress 정책 (모든 인바운드 차단)
    - nginx-ingress → 앱 서비스 허용 정책
    - 외부 Egress 허용 정책 (DB, 외부 API 통신)

---

## Phase 9 — 운영 안정성 강화 (Node Affinity, PDB, HPA, Helm)

### 41. Node Affinity + Pod Anti-Affinity 적용

**목적:** 서비스 특성에 맞는 노드 배치 선호도 설정 + Pod 분산 보장

**설계 결정:**
- `required`(하드) 대신 `preferred`(소프트) 방식 채택
  - 이유: hard constraint는 해당 노드 장애 시 Pod이 다른 노드에 폴백 불가 → 서비스 중단 위험
  - preferred는 가능하면 해당 노드에, 없으면 다른 노드에도 스케줄링 허용

**노드 역할 구분 (워커 4개 기준):**
```
worker1, worker2, worker3 → node-role=app  (Java Spring 서비스)
worker4                   → node-role=ai   (Python AI 서비스)
```

**수정된 파일:**

`v3/k8s/module-api/deployment.yaml`, `v3/k8s/module-chat/deployment.yaml` — `spec.template.spec`에 추가:
```yaml
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      preference:
        matchExpressions:
        - key: node-role
          operator: In
          values: ["app"]
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchLabels:
            app: module-api   # 또는 module-chat
        topologyKey: kubernetes.io/hostname
```

`v3/k8s/fastapi/deployment.yaml` — nodeAffinity values를 `["ai"]`로 설정

**노드 추가 후 라벨 설정:**
```bash
kubectl label node <worker1> <worker2> <worker3> node-role=app
kubectl label node <worker4> node-role=ai
```

---

### 42. PDB (Pod Disruption Budget) 적용

**목적:** 노드 drain(유지보수) 또는 롤링 업데이트 중 최소 Pod 수 보장

**문제 상황:** 노드 2개에 Pod 2개 운영 중 drain 발생 시 순간적으로 Pod 0개 → 서비스 중단 가능
**해결:** `minAvailable: 1` 설정 시 K8s가 eviction 요청을 블로킹 → 최소 1개 항상 유지

**생성된 파일:**
- `v3/k8s/module-api/pdb.yaml`
- `v3/k8s/module-chat/pdb.yaml`
- `v3/k8s/fastapi/pdb.yaml`

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: module-api-pdb
  namespace: klosetlab
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: module-api
```

---

### 43. metrics-server 설치

**목적:** HPA가 CPU/Memory 메트릭을 수집하기 위한 전제 조건 컴포넌트

**문제:** kubeadm으로 구성된 클러스터는 kubelet TLS 인증서가 self-signed → metrics-server가 거부
**해결:** `--kubelet-insecure-tls` 옵션 패치

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml
kubectl patch deployment metrics-server -n kube-system \
  --type='json' \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--kubelet-insecure-tls"}]'
```

설치 확인: `kubectl top nodes` 에서 CPU/Memory 수치 확인

---

### 44. Helm Chart 마이그레이션

**목적:** raw YAML → Helm Chart로 전환해 이미지 태그, 리소스, HPA 설정을 `values.yaml` 한 곳에서 관리

**생성된 파일 구조:**
```
v3/helm/
├── module-api/
│   ├── Chart.yaml
│   ├── values.yaml
│   └── templates/
│       ├── deployment.yaml   ← {{ .Values.image.tag }}, {{ .Values.resources }} 등 템플릿화
│       ├── service.yaml
│       ├── ingress.yaml
│       ├── hpa.yaml          ← {{- if .Values.hpa.enabled }} 조건부 생성
│       └── pdb.yaml
├── module-chat/  (동일 구조)
└── fastapi/      (동일 구조)
```

**values.yaml 핵심 항목:**
```yaml
image:
  repository: 862012315401.dkr.ecr.ap-northeast-2.amazonaws.com/klosetlab/module-api
  tag: "30d537..."       ← GitHub Actions가 배포마다 이 값만 업데이트

replicaCount: 2          ← 초기값, HPA가 런타임에 관리

resources:
  requests: { cpu: 250m, memory: 768Mi }
  limits:   { cpu: 500m, memory: 2Gi }

hpa:
  enabled: true
  minReplicas: 2
  maxReplicas: 5
  targetCPUUtilizationPercentage: 70
```

**GitHub Actions 변경** (`deploy-api.yml`, `deploy-chat.yml`, `deploy.yml`):
```yaml
# 변경 전: deployment.yaml의 image 필드 sed
sed -i "s|image: .../deployment.yaml"

# 변경 후: values.yaml의 tag 필드만 업데이트
sed -i "s|tag: .*|tag: \"$IMAGE_TAG\"|" infra/v3/helm/module-api/values.yaml
git add v3/helm/module-api/values.yaml
```

**ArgoCD Application 변경** (`v3/argocd/apps/*.yaml`):
```yaml
# 변경 전
source:
  path: v3/k8s/module-api

# 변경 후
source:
  path: v3/helm/module-api
  helm:
    valueFiles:
    - values.yaml
```

---

### 45. HPA (Horizontal Pod Autoscaler) 적용

**목적:** CPU 사용률 70% 초과 시 Pod 자동 증가, 트래픽 감소 시 자동 축소

| 서비스 | minReplicas | maxReplicas | 기준 CPU |
|--------|-------------|-------------|---------|
| module-api | 2 | 5 | 70% |
| module-chat | 2 | 5 | 70% |
| fastapi | 2 | 4 | 70% |

**HPA + ArgoCD 충돌 문제 및 해결:**
- 문제: HPA가 `spec.replicas`를 런타임에 변경 → ArgoCD selfHeal이 Git 값(replicas: 2)으로 강제 복원 → 스케일아웃 무력화
- 해결: ArgoCD Application에 `ignoreDifferences` 추가

```yaml
# v3/argocd/apps/module-api.yaml
ignoreDifferences:
- group: apps
  kind: Deployment
  jsonPointers:
  - /spec/replicas   # ArgoCD가 이 필드 변경을 감지하지 않음
```

---

## 최종 상태

| 서비스 | 상태 | 엔드포인트 |
|--------|------|-----------|
| module-api | ✅ 2/2 Running | https://v3.klosetlab.site/api |
| module-chat | ✅ 2/2 Running | https://v3.klosetlab.site/ws |
| fastapi | ✅ 2/2 Running | https://v3.klosetlab.site/ai |
| TLS (HTTPS) | ✅ Ready | cert-manager 자동 발급 |
| Kafka | ✅ Running | 10.0.21.135:9092 |
| ArgoCD | ✅ Synced/Healthy | |
| ECR 토큰 갱신 | ✅ 10시간마다 자동 | CronJob |
