# v3 쿠버네티스 인프라 설계 문서

> 이 문서는 v3 인프라 구축 과정에서의 설계 결정, 아키텍처, 각 컴포넌트 선택 이유를 기록한 포트폴리오 자료입니다.

---

## 1. 전체 아키텍처 개요

```
인터넷
  │
  ▼
Bastion EC2 (3.38.20.22)
  ├── nginx (HTTP :80)  → K8s NodePort :32496 (HTTP)
  └── nginx (TCP :443)  → K8s NodePort :32495 (HTTPS 패스스루)
         │
         ▼
  K8s Cluster (kubeadm)
  ├── Master Node  (10.0.11.26)
  └── Worker Nodes (10.0.12.235, 10.0.11.192)
         │
         ▼
  nginx-ingress Controller
  ├── /api  → module-api  Service (ClusterIP :8080)
  ├── /ws   → module-chat Service (ClusterIP :8081)
  └── /ai   → fastapi     Service (ClusterIP :8000)
         │
         ▼
  각 서비스 Pod (replicas: 2)
  ├── module-api  (Spring Boot)
  ├── module-chat (Spring Boot, WebSocket)
  └── fastapi     (Python FastAPI)
         │
         ▼
  인프라 서비스 (VPC 내부 EC2)
  ├── MySQL RDS      (10.x.x.x:3306)
  ├── Redis          (10.0.21.86:6379)
  ├── MongoDB        (10.0.21.94:27017)
  ├── Kafka          (10.0.21.135:9092)
  └── Qdrant         (10.0.21.117:6333)
```

---

## 2. 클러스터 구성 — kubeadm 선택 이유

### kubeadm vs EKS 비교

| 항목 | kubeadm (선택) | EKS |
|------|----------------|-----|
| 비용 | EC2 비용만 | EKS 클러스터 + EC2 ($0.10/hr 추가) |
| 컨트롤 플레인 | 직접 관리 | AWS 완전 관리 |
| 학습 효과 | K8s 내부 구조 이해 | 추상화 높음 |
| 설정 유연성 | 높음 | 제한적 |

**선택 이유**: 팀 프로젝트 예산 한계 + K8s 내부 구조 직접 학습 목적.

### 클러스터 구성
- **Master 1대**: etcd, kube-apiserver, kube-controller-manager, kube-scheduler
- **Worker 2대**: 실제 Pod 스케줄링 대상, nginx-ingress NodePort 노출

### 네트워크 플러그인 (CNI)
- **Flannel**: VXLAN 기반 오버레이 네트워크. 설정이 단순하고 kubeadm과 호환성이 좋다.
- Pod CIDR: `10.244.0.0/16`

---

## 3. Ingress 설계

### nginx-ingress Controller 선택 이유

K8s에서 외부 트래픽을 서비스로 라우팅하는 방법:

| 방법 | 설명 | 단점 |
|------|------|------|
| NodePort | 노드 IP:포트 직접 노출 | 포트 관리 복잡, 비표준 포트 |
| LoadBalancer | 클라우드 LB 자동 생성 | AWS ELB 비용 발생 (kubeadm 환경 미지원) |
| **Ingress** | L7 라우팅, 하나의 엔드포인트 | 별도 Controller 필요 |

nginx-ingress를 선택한 이유:
- 경로 기반 라우팅 (path-based routing) 가능 → 단일 도메인으로 여러 서비스 운영
- WebSocket 지원 내장
- cert-manager와 TLS 자동화 통합
- 어노테이션으로 세부 설정 가능 (timeout, body-size, rewrite 등)

### NodePort 구조

kubeadm 환경에서 nginx-ingress는 클라우드 LoadBalancer를 만들 수 없으므로 **NodePort** 방식으로 노출된다.

```
인터넷 → Bastion nginx → WorkerNode:32496 (HTTP) / WorkerNode:32495 (HTTPS)
                                    ↓
                         nginx-ingress Pod
                                    ↓
                         ClusterIP Service → App Pod
```

> 실제 프로덕션 AWS 환경이라면 NLB를 앞에 두고 NodePort를 직접 노출하지 않는다.

### 경로 설계

```
v3.klosetlab.site
├── /api/*  → module-api  (Spring Boot REST API)
├── /ws/*   → module-chat (WebSocket 서버)
└── /ai/*   → fastapi     (AI 처리 서버)
```

**프론트엔드(React)는 S3 + CloudFront**로 별도 배포해 K8s 클러스터 부하에서 분리했다.

### rewrite-target 적용 (fastapi)

Spring Boot는 코드에서 경로를 `/api/...`로 정의하므로 prefix 유지.
FastAPI는 `/clothes/analyze`처럼 prefix 없이 정의되어 있어 `/ai` prefix를 제거해야 함.

```yaml
# fastapi ingress
annotations:
  nginx.ingress.kubernetes.io/rewrite-target: /$2
path: /ai(/|$)(.*)   # (.*)가 $2에 캡처 → /$2로 rewrite
pathType: ImplementationSpecific
```

---

## 4. TLS 자동화 — cert-manager + Let's Encrypt

### 구성 요소

```
cert-manager (K8s 컨트롤러)
    │
    ├── ClusterIssuer (letsencrypt-prod)
    │       └── ACME 서버: https://acme-v02.api.letsencrypt.org
    │
    └── Certificate (klosetlab-tls)
            └── HTTP01 챌린지 방식
```

### HTTP01 챌린지 동작 원리

1. cert-manager가 K8s에 임시 Ingress + Pod 생성
2. Let's Encrypt가 `http://v3.klosetlab.site/.well-known/acme-challenge/<token>` 접근
3. 임시 Pod가 토큰으로 응답 → 도메인 소유 증명
4. 인증서 발급 → `klosetlab-tls` Secret에 저장
5. 임시 Ingress + Pod 자동 삭제

### 주의사항

nginx-ingress의 `ssl-redirect` 기능이 기본적으로 HTTP → HTTPS 리다이렉트를 하기 때문에 챌린지 경로도 리다이렉트될 수 있다. 이를 방지하기 위해 ClusterIssuer에 `ingressTemplate` 설정 필요:

```yaml
ingressTemplate:
  metadata:
    annotations:
      nginx.ingress.kubernetes.io/ssl-redirect: "false"
```

### Route53 서브도메인 위임

기존 계정의 `klosetlab.site` 호스팅 존에서 신규 계정의 `v3.klosetlab.site` 호스팅 존으로 NS 위임:

```
[기존 계정 Route53 - klosetlab.site]
v3    IN  NS  ns-xxx.awsdns-xx.com.   ← 레코드 이름은 "v3"만 입력 (FQDN 아님)
              ns-xxx.awsdns-xx.net.
              ns-xxx.awsdns-xx.co.uk.
              ns-xxx.awsdns-xx.org.

[신규 계정 Route53 - v3.klosetlab.site]
@     IN  A   3.38.20.22   (바스티온 공인 IP)
```

---

## 5. GitOps CI/CD 파이프라인

### 전체 흐름

```
개발자 코드 push (app repo: main 브랜치)
        │
        ▼
GitHub Actions (CI)
  1. 앱 빌드 (gradlew bootJar / npm run build)
  2. Docker 이미지 빌드
  3. ECR push (태그: git SHA — 롤백 가능)
  4. infra repo checkout (GITOPS_TOKEN 사용)
  5. sed로 deployment.yaml 이미지 태그 교체
  6. infra repo commit & push
        │
        ▼
infra repo (10-team-FFS-Cloud) 변경 감지
        │
        ▼
ArgoCD (CD)
  - 3분 주기 또는 webhook으로 변경 감지
  - 새 이미지 태그로 Rolling Update 실행
  - prune: 삭제된 리소스 자동 제거
  - selfHeal: 수동 변경 사항 자동 복구
```

### 이미지 태그 전략

`latest` 태그 사용을 지양하고 **git SHA를 태그로 사용**한다.

```bash
IMAGE_TAG=${{ github.sha }}
docker build -t $ECR_REGISTRY/$ECR_REPOSITORY:$IMAGE_TAG .
```

이유:
- 이전 버전으로 롤백 가능 (`kubectl rollout undo`)
- 배포된 버전이 어떤 코드인지 추적 가능
- `latest` 태그는 어떤 버전인지 구분 불가

### GitHub Secrets 구조

`V3_` prefix를 붙여 v2 시크릿과 구분:

```
V3_AWS_ACCESS_KEY_ID      - ECR push용 IAM 사용자
V3_AWS_SECRET_ACCESS_KEY
V3_AWS_REGION
V3_ECR_REGISTRY           - 계정ID.dkr.ecr.ap-northeast-2.amazonaws.com
V3_GITOPS_TOKEN           - infra repo 쓰기 권한 PAT
```

### App 레포 vs Infra 레포 분리 이유

| 분리 방식 | 이유 |
|-----------|------|
| App 레포에 코드 + 매니페스트 모두 | 간단하지만 코드 변경과 인프라 변경이 혼재 |
| **App 레포 + Infra 레포 분리** | 인프라 이력만 따로 관리, ArgoCD가 infra 레포만 감시 |

---

## 6. ECR 인증 — imagePullSecret 패턴

### 문제 상황

K8s 노드에 ECR Pull 권한 IAM Role이 부착되어 있었지만 Pod가 이미지를 가져오지 못했다.

### 원인

Docker 데몬은 EC2 Instance Metadata Service(IMDS)를 통해 IAM 자격증명을 자동으로 사용한다. 그러나 **containerd**(kubeadm 기본 CRI)는 IAM Role 자동 인증을 지원하지 않는다.

### 해결 구조

```
ECR 토큰 (12시간 유효)
    │
    ▼
kubectl create secret docker-registry ecr-registry-secret
    │
    ▼
Deployment.spec.template.spec.imagePullSecrets
  - name: ecr-registry-secret
    │
    ▼
kubelet → containerd → ECR 인증 성공
```

### 토큰 자동 갱신 (CronJob)

ECR 토큰이 12시간마다 만료되므로 K8s CronJob으로 자동 갱신:

```yaml
spec:
  schedule: "0 */10 * * *"   # 10시간마다 (만료 2시간 전)
  jobTemplate:
    spec:
      template:
        spec:
          serviceAccountName: ecr-token-refresh  # Secret 수정 RBAC 권한
          containers:
          - image: alpine/k8s:1.29.2              # aws + kubectl 포함
            command:
            - /bin/sh
            - -c
            - |
              ECR_TOKEN=$(aws ecr get-login-password --region ap-northeast-2)
              kubectl create secret docker-registry ecr-registry-secret \
                --docker-password=$ECR_TOKEN \
                --dry-run=client -o yaml | kubectl apply -f -
```

RBAC 구성:

```yaml
# ServiceAccount → Role → RoleBinding
Role rules:
- apiGroups: [""]
  resources: ["secrets"]
  verbs: ["get", "create", "patch", "delete"]
```

---

## 7. K8s Secret 관리

### 앱 시크릿 구조

각 서비스마다 별도의 Secret:

```
module-api-secret   (26개 환경변수: DB, Redis, Kafka, JWT, S3 등)
module-chat-secret  (18개 환경변수: DB, Redis, Kafka, JWT 등)
fastapi-secret      (42개 환경변수: DB, Redis, Kafka, Qdrant, AI API키 등)
```

```yaml
# Deployment에서 참조
envFrom:
- secretRef:
    name: module-api-secret   # 모든 키가 환경변수로 주입됨
```

### 시크릿 생성 방법

```bash
kubectl create secret generic module-api-secret \
  --from-literal=SPRING_DATASOURCE_URL=jdbc:mysql://... \
  --from-literal=JWT_SECRET=... \
  --namespace=klosetlab
```

> 실제 값은 AWS Secrets Manager나 Vault 같은 외부 시크릿 저장소로 관리하는 것이 베스트 프랙티스. 이번 프로젝트에서는 K8s Secret 직접 관리.

---

## 8. 리소스 설정 — Requests & Limits

### 설정 원칙

```yaml
resources:
  requests:   # 스케줄링 기준 (이만큼 보장)
    cpu: 250m
    memory: 512Mi
  limits:     # 최대 사용량 (초과 시 OOM Kill)
    cpu: 500m
    memory: 2Gi
```

| 개념 | 설명 |
|------|------|
| requests | 노드에 파드를 스케줄할 때 이 값이 확보 가능한지 확인 |
| limits | 컨테이너가 이 값을 초과하면 CPU는 throttle, 메모리는 OOM Kill |
| QoS Guaranteed | requests == limits → 최우선 보호 |
| QoS Burstable | requests < limits → 우선순위 중간 (우리 서비스 해당) |

### JVM 서비스 메모리 설정

Spring Boot는 JVM이 컨테이너 메모리 제한을 기준으로 힙을 자동 설정하지만 기본값(25%)이 너무 작다.

```yaml
env:
- name: JAVA_TOOL_OPTIONS
  value: "-Xms512m -Xmx1536m -XX:MetaspaceSize=128m -XX:MaxMetaspaceSize=256m"
```

컨테이너 2Gi 제한 내 메모리 분배:
- JVM Heap: 최대 1.5Gi
- Metaspace: 최대 256Mi
- JVM 내부/스레드: ~200Mi (여유분)

---

## 9. 헬스체크 — Liveness & Readiness Probe

### 두 Probe의 차이

| Probe | 실패 시 동작 | 역할 |
|-------|-------------|------|
| **livenessProbe** | 컨테이너 재시작 | 앱이 데드락/장애 상태인지 확인 |
| **readinessProbe** | 서비스에서 Pod 제외 | 트래픽 받을 준비가 됐는지 확인 |

### Spring Boot 설정

```yaml
livenessProbe:
  httpGet:
    path: /actuator/health
    port: 8080
  initialDelaySeconds: 60   # JVM 기동 시간 확보
  periodSeconds: 10
readinessProbe:
  httpGet:
    path: /actuator/health
    port: 8080
  initialDelaySeconds: 60
  periodSeconds: 10
```

> **주의**: Spring Boot Actuator의 `/actuator/health`는 Kafka, DB 등 의존성 상태를 포함한다. Kafka 연결 실패 시 health가 DOWN을 반환해 Probe가 실패하므로, 의존 서비스가 모두 정상이어야 Pod가 Ready 상태가 된다.

### FastAPI 설정

```yaml
livenessProbe:
  httpGet:
    path: /health   # FastAPI 앱이 직접 구현한 헬스 엔드포인트
    port: 8000
  initialDelaySeconds: 60
  periodSeconds: 10
```

---

## 10. Rolling Update 전략

```yaml
spec:
  strategy:
    type: RollingUpdate   # 기본값
    rollingUpdate:
      maxUnavailable: 1   # 동시에 최대 1개 Pod 중단 허용
      maxSurge: 1         # 동시에 최대 1개 초과 Pod 허용
```

배포 흐름 (replicas: 2):
1. 새 Pod 1개 생성 (총 3개)
2. 새 Pod Readiness 통과
3. 기존 Pod 1개 종료 (총 2개)
4. 나머지 기존 Pod도 교체

**무중단 배포** 가능.

---

## 11. ArgoCD 설계

### ArgoCD Application 3개 등록

```
argocd/
├── fastapi       → infra repo: v3/k8s/fastapi/
├── module-api    → infra repo: v3/k8s/module-api/
└── module-chat   → infra repo: v3/k8s/module-chat/
```

### Sync 정책

```yaml
syncPolicy:
  automated:
    prune: true      # Git에서 삭제된 리소스 K8s에서도 삭제
    selfHeal: true   # 수동으로 K8s 리소스를 바꿔도 Git 상태로 복원
```

### GitOps의 핵심 원칙

- **Single Source of Truth**: infra repo의 YAML이 클러스터의 실제 상태를 정의
- 개발자가 K8s에 직접 `kubectl apply` 하지 않아도 됨
- 배포 이력이 Git 커밋으로 추적 가능
- 문제 발생 시 `git revert`로 이전 배포 상태로 복원 가능

---

## 12. 네임스페이스 구조

```
klosetlab      ← 서비스 워크로드 (module-api, module-chat, fastapi)
argocd         ← ArgoCD 컨트롤 플레인
ingress-nginx  ← nginx-ingress Controller
cert-manager   ← TLS 자동화 Controller
```

### 네임스페이스 분리 이유
- RBAC 범위를 서비스별로 제한 가능
- 리소스 격리 (Secret이 다른 네임스페이스에서 접근 불가)
- kubectl 명령 시 `-n klosetlab` 으로 범위 한정

---

## 13. 보안 구성

### IAM 역할 분리

| 역할 | 대상 | 권한 |
|------|------|------|
| K8s 노드 IAM Role | EC2 Worker 인스턴스 | ECR Pull, CloudWatch Logs |
| GitHub Actions IAM User | CI/CD | ECR Push (특정 레포지토리만) |

### 보안 그룹 설계

```
바스티온 (sg-0b333c25a27c1f23c)
  inbound: 22(SSH), 80(HTTP), 443(HTTPS) from 0.0.0.0/0

K8s 워커 노드 (sg-0aabfdd7fb2437864)
  inbound: 바스티온 SG에서 NodePort 범위 (30000-32767)
           마스터 SG에서 kubelet, kube-proxy 포트

인프라 서비스 (각 EC2별 SG)
  inbound: K8s 워커 SG에서 해당 서비스 포트만
  예) Kafka: 9092 from sg-0aabfdd7fb2437864
      Redis:  6379 from sg-0aabfdd7fb2437864
```

---

## 14. Kafka 설계 결정 사항

### KRaft 모드 선택

기존 Kafka는 메타데이터 관리에 **Zookeeper**를 별도로 필요로 했다. Kafka 3.3부터 안정화된 **KRaft 모드**는 Zookeeper 없이 Kafka 자체가 메타데이터를 관리한다.

| | Zookeeper 모드 | KRaft 모드 (선택) |
|-|----------------|-------------------|
| 컴포넌트 | Kafka + Zookeeper 2개 프로세스 | Kafka 1개 프로세스 |
| 복잡도 | 높음 | 낮음 |
| 프로덕션 권장 | Kafka 3.5 이전 | Kafka 3.3+ |

### Topic 파티션 설계

```
ai.clothes.analyze.request   partitions: 1
  → AI 분석 요청 큐. 순서 보장이 중요하지 않고 단방향 전송.

ai.clothes.analyze.result    partitions: 3
  → Spring Boot consumer concurrency: 3 에 맞춤.
    파티션 수 = consumer thread 수 일 때 최대 병렬 처리 가능.
```

---

## 15. 앞으로 개선할 수 있는 것들 (포트폴리오 확장 포인트)

| 항목 | 현재 | 개선 방향 |
|------|------|-----------|
| 시크릿 관리 | K8s Secret 직접 생성 | AWS Secrets Manager + External Secrets Operator |
| 모니터링 | 없음 | Prometheus + Grafana (Helm chart) |
| 로그 수집 | 없음 | Fluent Bit → CloudWatch Logs |
| K8s 인증서 | cert-manager | 동일 (적절) |
| ECR 인증 | CronJob | IRSA (IAM Role for Service Account) — EKS 환경 |
| 트래픽 관리 | nginx-ingress 기본 | Istio Service Mesh (Circuit Breaker, mTLS) |
| 클러스터 HA | Master 1대 | Master 3대 (etcd 쿼럼) |
| HPA | 없음 | HorizontalPodAutoscaler (CPU/메모리 기반 자동 스케일) |
