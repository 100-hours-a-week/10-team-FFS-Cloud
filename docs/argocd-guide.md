# ArgoCD GitOps 완전 가이드

> 이 프로젝트에서 ArgoCD가 어떻게 동작하는지, 왜 이렇게 설계했는지 완벽하게 이해하기 위한 문서

---

## 1. ArgoCD란 무엇인가

### 핵심 한 줄 정의
**"Git이 K8s 클러스터의 유일한 진실(Single Source of Truth)이 되도록 강제하는 도구"**

### GitOps vs 기존 배포 방식 비교

| 항목 | 기존 방식 (Push) | GitOps (Pull) |
|------|-----------------|---------------|
| 배포 주체 | CI 서버가 K8s에 직접 push | ArgoCD가 Git을 감시하다 pull |
| K8s 접근 권한 | CI 서버가 kubeconfig 보유 | CI 서버는 Git만 수정, K8s 접근 불필요 |
| 현재 상태 파악 | K8s가 곧 실제 상태 | Git이 원하는 상태, K8s가 실제 상태 |
| 드리프트 감지 | 누군가 `kubectl apply`해도 모름 | ArgoCD가 감지 후 자동 복원 |
| 롤백 | 이전 이미지 tag를 알아야 함 | `git revert`로 즉시 롤백 |
| 감사 로그 | CI 로그에만 있음 | Git 커밋 히스토리가 배포 기록 |

### ArgoCD가 해결하는 핵심 문제
```
문제: "지금 클러스터에 실제로 뭐가 배포되어 있는지 확신할 수 있나?"
해결: Git에 있는 내용 = 클러스터 상태. Git이 진실이다.
```

---

## 2. 이 프로젝트의 ArgoCD 아키텍처

### 전체 CI/CD 파이프라인

```
┌─────────────────────────────────────────────────────────────────┐
│                        개발자                                     │
│  git push → app repo (main)                                     │
└────────────────────────┬────────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                   GitHub Actions (CI)                            │
│                                                                  │
│  1. Docker build                                                │
│  2. ECR push (tag = git SHA)                                    │
│     862012315401.dkr.ecr.ap-northeast-2.amazonaws.com/          │
│     klosetlab/{service}:{git-sha}                               │
│  3. infra repo 체크아웃                                          │
│  4. sed로 deployment.yaml 이미지 태그 교체                        │
│  5. infra repo commit & push                                    │
└────────────────────────┬────────────────────────────────────────┘
                         │  Git push to infra repo
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│              infra repo (10-team-FFS-Cloud)                     │
│                                                                  │
│  v3/argocd/                                                     │
│  ├── app-of-apps.yaml          ← 최상위 Application             │
│  └── apps/                                                      │
│      ├── module-api.yaml       ← Child Application              │
│      ├── module-chat.yaml      ← Child Application              │
│      └── fastapi.yaml          ← Child Application              │
│                                                                  │
│  v3/k8s/                                                        │
│  ├── module-api/               ← ArgoCD가 여기를 감시            │
│  │   ├── deployment.yaml       ← 이미지 태그가 여기에 업데이트됨  │
│  │   ├── service.yaml                                           │
│  │   └── ingress.yaml                                           │
│  ├── module-chat/                                               │
│  └── fastapi/                                                   │
└────────────────────────┬────────────────────────────────────────┘
                         │  ArgoCD가 3분마다 감시 (또는 webhook)
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ArgoCD                                      │
│              (K8s master 노드, argocd namespace)                │
│                                                                  │
│  앱 상태 비교:                                                   │
│  Git(원하는 상태) ≠ K8s(실제 상태)  →  자동 Sync 트리거         │
│  Git(원하는 상태) = K8s(실제 상태)  →  Synced / Healthy         │
└────────────────────────┬────────────────────────────────────────┘
                         │  kubectl apply
                         ▼
┌─────────────────────────────────────────────────────────────────┐
│                   K8s 클러스터                                    │
│              (klosetlab namespace)                               │
│                                                                  │
│  Rolling Update 실행:                                           │
│  새 Pod 기동 → Readiness Probe 통과 → 구 Pod 종료               │
│  (무중단 배포)                                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. App of Apps 패턴 — 핵심 설계

### 왜 App of Apps인가

단순히 ArgoCD Application을 `kubectl apply`로 등록하면 **ArgoCD 자체 설정이 Git 밖에 있다**는 문제가 생깁니다.

```
문제: ArgoCD Application이 클러스터에만 존재
     → 클러스터 재구성 시 Application 3개를 다시 kubectl로 등록해야 함
     → ArgoCD 설정 자체가 GitOps되지 않음
```

App of Apps 패턴으로 이를 해결합니다:

```
app-of-apps (최상위)
  → v3/argocd/apps/ 폴더 감시
  → module-api Application 자동 생성/관리
  → module-chat Application 자동 생성/관리
  → fastapi Application 자동 관리
```

**장점:**
- `kubectl apply -f v3/argocd/app-of-apps.yaml` 명령어 하나로 전체 GitOps 재구성
- ArgoCD 설정 자체가 Git에 있어 버전 관리 가능
- 서비스 추가 시 `v3/argocd/apps/`에 파일만 추가하면 됨

### 파일 구조

```
v3/argocd/
├── app-of-apps.yaml          # 최상위 Application
│                             # → v3/argocd/apps/ 폴더를 argocd namespace에 배포
└── apps/
    ├── module-api.yaml       # sync-wave: "0" (첫 번째 배포)
    ├── module-chat.yaml      # sync-wave: "1" (두 번째 배포)
    └── fastapi.yaml          # sync-wave: "2" (세 번째 배포)
```

---

## 4. Sync Wave — 배포 순서 제어

### 왜 순서가 필요한가

```
module-api → module-chat → fastapi
```

- module-chat은 module-api와 Kafka를 통해 통신 → module-api가 먼저 Running이어야 안전
- fastapi는 독립적이지만, 인프라 자원 경합을 방지하기 위해 마지막 배포

### Sync Wave 동작 방식

```yaml
# wave 0: 가장 먼저 배포 시작
argocd.argoproj.io/sync-wave: "0"

# wave 1: wave 0의 리소스가 Healthy가 된 후 배포
argocd.argoproj.io/sync-wave: "1"

# wave 2: wave 1의 리소스가 Healthy가 된 후 배포
argocd.argoproj.io/sync-wave: "2"
```

ArgoCD는 각 wave의 리소스가 `Healthy` 상태가 되어야 다음 wave로 진행합니다.

---

## 5. SyncPolicy 설정 해설

```yaml
syncPolicy:
  automated:
    prune: true      # Git에서 파일 삭제 시 K8s 리소스도 삭제
    selfHeal: true   # kubectl로 수동 변경해도 Git 상태로 자동 복원
  syncOptions:
  - CreateNamespace=true   # namespace가 없으면 자동 생성
  retry:
    limit: 3               # Sync 실패 시 최대 3회 재시도
    backoff:
      duration: 10s        # 첫 재시도: 10초 후
      maxDuration: 3m      # 최대 대기: 3분
      factor: 2            # 지수 백오프: 10s → 20s → 40s
```

**prune의 중요성:**
```
예시: module-api Ingress를 Prefix → ImplementationSpecific으로 변경하면서
     기존 ingress.yaml 파일명을 바꾸면
     prune: true  → 기존 Ingress 삭제 + 새 Ingress 생성 (올바름)
     prune: false → 기존 Ingress + 새 Ingress 공존 (중복 발생)
```

**selfHeal의 중요성:**
```
예시: 긴급 상황에서 `kubectl edit deployment module-api -n klosetlab`으로
     replicas를 1로 줄이면
     selfHeal: true  → ArgoCD가 감지 후 Git의 replicas: 2로 복원
     selfHeal: false → 수동 변경이 그대로 유지되어 Git과 불일치 상태 지속
```

---

## 6. 이미지 태그 전략

### Git SHA 태깅

```
이미지 태그 = git commit SHA (예: 0ba86719fdc42aebc2046e3f67e6798567b97023)
```

**장점:**
- 어떤 코드가 배포됐는지 git log로 즉시 확인 가능
- `git revert`로 롤백하면 이미지도 자동으로 이전 버전으로
- `latest` 태그는 어떤 버전인지 불분명 → 디버깅 불가

**배포 흐름:**
```bash
# GitHub Actions에서 자동으로 실행
IMAGE_TAG=$(git rev-parse HEAD)  # SHA 추출

# deployment.yaml의 이미지 태그를 새 SHA로 교체
sed -i "s|image: .*/klosetlab/module-api:.*|image: .../module-api:${IMAGE_TAG}|" \
  v3/k8s/module-api/deployment.yaml

# 변경사항 commit & push → ArgoCD가 감지 → 자동 배포
git commit -m "ci: update module-api image to ${IMAGE_TAG}"
git push
```

---

## 7. ArgoCD 상태 개념

### Application 상태

| 상태 | 의미 |
|------|------|
| **Synced** | Git 상태 = K8s 실제 상태 |
| **OutOfSync** | Git과 K8s가 다름 (배포 중이거나 수동 변경됨) |
| **Unknown** | 상태 확인 불가 |

### Health 상태

| 상태 | 의미 |
|------|------|
| **Healthy** | 모든 Pod가 Running, Probe 정상 |
| **Progressing** | Rolling Update 진행 중 |
| **Degraded** | Pod 일부 또는 전체 장애 |
| **Missing** | 리소스가 K8s에 없음 |

### 상태 확인 명령어

```bash
# 전체 Application 상태
kubectl get applications -n argocd

# 상세 상태 (OutOfSync 원인 파악)
kubectl describe application module-api -n argocd

# ArgoCD CLI 사용 시
argocd app list
argocd app get module-api
argocd app sync module-api  # 수동 강제 sync
```

---

## 8. 롤백 전략

### 방법 1: Git revert (권장)

```bash
# 인프라 레포에서
git log --oneline  # 롤백할 커밋 SHA 확인
git revert <commit-sha>  # 이전 이미지 태그로 되돌리는 커밋 생성
git push

# ArgoCD가 감지 → 자동으로 이전 버전 배포
```

**장점:** 롤백 자체가 Git 기록에 남음. 언제, 왜 롤백했는지 추적 가능.

### 방법 2: ArgoCD History 롤백

```bash
# ArgoCD가 보관 중인 이전 배포 기록으로 롤백
argocd app rollback module-api <deployment-id>

# 주의: selfHeal: true이면 ArgoCD가 Git 상태(최신)로 다시 복원하므로
#       영구 롤백을 원하면 Git도 함께 수정해야 함
```

### 방법 3: kubectl rollout (임시)

```bash
kubectl rollout undo deployment/module-api -n klosetlab

# 주의: selfHeal이 감지해서 Git 상태로 덮어씀
#       응급 임시 조치로만 사용
```

---

## 9. 수동 ArgoCD sync 방법

### ArgoCD가 자동으로 감지 못할 때

```bash
# kubectl patch로 강제 sync 트리거
kubectl patch application module-api -n argocd \
  --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'

# 전체 Application sync
for app in module-api module-chat fastapi; do
  kubectl patch application $app -n argocd \
    --type merge \
    -p '{"operation":{"sync":{"revision":"HEAD"}}}'
done
```

---

## 10. App of Apps 최초 등록 방법

클러스터를 처음 구성하거나 재구성할 때:

```bash
# 1. ArgoCD 설치
kubectl create namespace argocd
kubectl apply -n argocd \
  -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 2. app-of-apps 단 하나만 등록
kubectl apply -f v3/argocd/app-of-apps.yaml

# 3. 이후 자동으로:
#    app-of-apps → v3/argocd/apps/ 감시
#    → module-api, module-chat, fastapi Application 자동 생성
#    → 각 Application이 v3/k8s/{service}/ 감시
#    → K8s에 Deployment, Service, Ingress 자동 배포
```

---

## 11. ArgoCD UI 접속

```bash
# ArgoCD UI 포트포워딩 (로컬 PC에서 실행)
ssh -i ~/.ssh/klosetlab-key.pem \
    -J ubuntu@3.38.20.22 ubuntu@10.0.11.26 \
    -L 8080:localhost:8080 &

# 마스터 노드에서 실행
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 브라우저: https://localhost:8080
# 초기 비밀번호
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```

UI에서 확인할 수 있는 것:
- 각 Application의 sync 상태 (Synced / OutOfSync)
- 리소스 트리 (Deployment → ReplicaSet → Pod 계층 구조)
- 최근 sync 이력 및 오류 메시지
- 수동 Sync / Rollback 버튼

---

## 12. 포트폴리오 어필 포인트

### 설계 의도를 설명할 수 있어야 하는 것들

**Q: "ArgoCD에서 automated sync를 켠 이유는?"**

> "배포는 코드 변경(CI)과 완전히 분리되어야 합니다. GitHub Actions는 코드를 빌드해서 Git에 이미지 태그를 업데이트하는 것까지만 담당하고, 실제 K8s 배포는 ArgoCD가 Git을 pull해서 처리합니다. 이렇게 하면 CI 서버가 K8s kubeconfig를 직접 가질 필요가 없어 보안이 강화되고, Git이 모든 배포의 기록이 됩니다."

**Q: "selfHeal은 왜 켰나요?"**

> "운영 중 긴급 상황에서 kubectl로 수동 변경을 하면 Git과 클러스터 상태가 달라집니다. selfHeal이 없으면 이 드리프트가 누적돼 '실제로 뭐가 배포됐는지'를 알 수 없게 됩니다. selfHeal을 켜서 Git이 항상 진실이 되도록 강제했습니다."

**Q: "App of Apps 패턴을 쓴 이유는?"**

> "ArgoCD Application 자체를 kubectl로만 등록하면 K8s 클러스터를 새로 구성할 때 수작업이 필요합니다. App of Apps 패턴으로 Application 매니페스트 자체도 Git에 저장하면, `kubectl apply -f app-of-apps.yaml` 하나로 전체 GitOps 파이프라인이 자동으로 재구성됩니다."

**Q: "Sync Wave를 쓴 이유는?"**

> "module-chat은 module-api와 Kafka를 통해 통신하기 때문에 module-api가 먼저 기동되어야 초기 연결 에러를 방지할 수 있습니다. Sync Wave로 배포 순서를 module-api(0) → module-chat(1) → fastapi(2)로 제어했습니다."

**Q: "롤백은 어떻게 하나요?"**

> "이미지 태그를 git SHA로 관리하기 때문에 `git revert`로 이전 커밋으로 돌아가면 ArgoCD가 자동으로 이전 이미지를 배포합니다. 롤백 자체가 Git 커밋으로 기록되어 누가, 언제, 왜 롤백했는지 모두 추적 가능합니다."

### 이 프로젝트에서 구현한 GitOps 성숙도

| 레벨 | 항목 | 구현 여부 |
|------|------|-----------|
| 기본 | ArgoCD automated sync | ✅ |
| 기본 | Git SHA 이미지 태그 | ✅ |
| 중급 | prune + selfHeal | ✅ |
| 중급 | App of Apps 패턴 | ✅ |
| 중급 | Sync Wave 배포 순서 | ✅ |
| 중급 | Retry with backoff | ✅ |
| 고급 | ArgoCD Notifications (Slack 알림) | 미구현 |
| 고급 | ArgoCD Image Updater | 미구현 |
| 고급 | Multi-cluster 관리 | 미구현 |

---

## 13. 현재 인프라 구성 요약

```
GitHub (app repos)
  ├── 10-team-FFS-BE-java (module-api)
  ├── 10-team-FFS-BE-chat (module-chat)
  └── 10-team-FFS-AI     (fastapi)
         │
         │ CI: GitHub Actions (빌드 + ECR push + infra repo 이미지 태그 업데이트)
         ▼
GitHub (infra repo: 10-team-FFS-Cloud)
  └── v3/
      ├── argocd/
      │   ├── app-of-apps.yaml     ← 클러스터 재구성 시 이것 하나만 적용
      │   └── apps/
      │       ├── module-api.yaml
      │       ├── module-chat.yaml
      │       └── fastapi.yaml
      └── k8s/
          ├── module-api/          ← ArgoCD가 감시
          ├── module-chat/         ← ArgoCD가 감시
          └── fastapi/             ← ArgoCD가 감시
         │
         │ CD: ArgoCD (Git 감시 → K8s apply)
         ▼
AWS K8s 클러스터 (kubeadm, 1 master + 2 workers)
  └── klosetlab namespace
      ├── module-api    (2 replicas)
      ├── module-chat   (2 replicas)
      └── fastapi       (2 replicas)
```
