# Kubernetes 인프라 운영 포트폴리오

> 프로젝트: Kloset (패션 커머스 플랫폼)
> 기간: 2026년 3월
> 역할: 인프라 엔지니어 (K8s 클러스터 구축 · 운영)
> 스택: Kubernetes 1.32 · ArgoCD · Helm · Calico · Prometheus · k6

---

## 목차

1. [K8s 클러스터 구축 및 노드 역할 분리](#1-k8s-클러스터-구축-및-노드-역할-분리)
2. [GitOps 파이프라인 with ArgoCD + Helm](#2-gitops-파이프라인-with-argocd--helm)
3. [HPA + PDB로 자동 확장 및 가용성 보장](#3-hpa--pdb로-자동-확장-및-가용성-보장)
4. [JVM 메모리 분석 및 최적화 (핵심 스토리)](#4-jvm-메모리-분석-및-최적화-핵심-스토리)
5. [NetworkPolicy Default Deny + Whitelist](#5-networkpolicy-default-deny--whitelist)
6. [장애 대응 경험 3가지](#6-장애-대응-경험-3가지)

---

## 1. K8s 클러스터 구축 및 노드 역할 분리

### 배경

기존 EC2 단순 배포 구조에서 Kubernetes로 마이그레이션. 서비스가 Spring Boot(module-api, module-chat)와 FastAPI(AI 추천) 이종 스택으로 구성되어 있어, **리소스 경합 없이 워크로드를 분리**할 필요가 있었다.

### 구현

**클러스터 구성: master 1대 + worker 4대**

```
[master]  ip-10-0-11-26   (control-plane)
[worker1] ip-10-0-11-192  node-role=app   ← Spring Boot
[worker2] ip-10-0-12-235  node-role=app   ← Spring Boot
[worker3] ip-10-0-11-177  node-role=app   ← Spring Boot
[worker4] ip-10-0-12-34   node-role=ai    ← FastAPI (AI)
```

**Node Label 부여**
```bash
kubectl label node ip-10-0-11-192 node-role=app
kubectl label node ip-10-0-12-34  node-role=ai
```

**Preferred NodeAffinity 적용 (module-api)**
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
            app: module-api
        topologyKey: kubernetes.io/hostname
```

### 선택 이유 및 트레이드오프

| 선택지 | 채택 여부 | 이유 |
|--------|----------|------|
| `required` NodeAffinity | ❌ | app 노드 전체 장애 시 pod 스케줄 불가 → 서비스 다운 |
| `preferred` NodeAffinity | ✅ | app 노드 우선 배치, 불가능 시 다른 노드 fallback |
| Taint/Toleration | ❌ | calico, kube-proxy 등 시스템 pod도 차단됨. GPU처럼 특수 하드웨어 격리 목적에 적합 |
| required Pod Anti-Affinity | ❌ | 노드 수(3)보다 replica가 많으면(4+) 스케줄링 자체가 불가 |

### 면접 스크립트

> "Spring Boot와 FastAPI가 같은 노드에서 CPU를 경합하는 문제를 해결하기 위해 노드 역할을 분리했습니다. required 조건 대신 preferred를 선택한 이유는, required로 설정하면 app 노드가 모두 내려갔을 때 pod가 아예 뜨지 못해 서비스 전체가 다운되기 때문입니다. preferred는 정상 상황에서는 원하는 노드에 배치되고, 장애 상황에서는 다른 노드에 fallback하는 고가용성 전략입니다."

---

## 2. GitOps 파이프라인 with ArgoCD + Helm

### 배경

수동 kubectl apply로 배포하던 방식을 Git 단일 소스 기반 자동화로 전환. 이미지 태그 변경 → 자동 배포까지 사람 개입 없이 처리.

### 파이프라인 흐름

```
코드 Push
  → GitHub Actions (빌드 + ECR Push + image tag 커밋)
  → ArgoCD가 Git 변경 감지
  → Helm chart 렌더링 후 K8s 자동 배포
```

### HPA 충돌 문제 해결

ArgoCD가 Git의 `replicaCount: 2`를 보고, HPA가 스케일한 실제 replica(예: 4)를 2로 되돌리는 문제 발생.

```yaml
# argocd/apps/module-api.yaml
ignoreDifferences:
- group: apps
  kind: Deployment
  jsonPointers: [/spec/replicas]   # replica는 HPA에게 위임, ArgoCD는 무시
```

### 면접 스크립트

> "GitOps를 도입하면서 HPA와 ArgoCD 간 충돌 문제를 겪었습니다. ArgoCD는 Git 상태를 정답으로 보기 때문에, HPA가 트래픽에 맞게 늘린 replica를 Git 값으로 되돌리려 했습니다. ignoreDifferences로 replica 필드는 ArgoCD 관리에서 제외해 HPA와 GitOps가 공존하도록 해결했습니다."

---

## 3. HPA + PDB로 자동 확장 및 가용성 보장

### 설정값

| 서비스 | minReplicas | maxReplicas | CPU 임계값 |
|--------|-------------|-------------|-----------|
| module-api | 2 | 5 | 70% |
| module-chat | 2 | 5 | 70% |
| fastapi | 2 | 4 | 70% |

```yaml
# HPA
metrics:
- type: Resource
  resource:
    name: cpu
    target:
      type: Utilization
      averageUtilization: 70

# PDB
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: module-api
```

### PDB가 막아준 것

kubectl drain으로 노드를 비울 때, replica 2개가 같은 노드에 있으면 순간적으로 0개가 될 수 있다. PDB `minAvailable: 1`은 drain이나 롤링 업데이트 중에도 최소 1개 pod는 반드시 살아있도록 K8s가 강제 보장한다.

### 실증: DiskPressure 인시던트에서 PDB 효과

롤링 업데이트 도중 두 노드에서 DiskPressure 발생 → 해당 노드의 pod 40개 동시 eviction.
그럼에도 **k6 에러율 0% 유지** → 다른 노드의 pod가 서비스를 지속, PDB가 최소 가용성 보장.

### 면접 스크립트

> "PDB의 효과를 실제 장애에서 확인했습니다. 롤링 업데이트 중 디스크 부족으로 두 노드에서 pod 40개가 동시에 eviction됐는데, 나머지 노드에 있는 pod들 덕분에 에러율 0%를 유지했습니다. PDB가 없었다면 drain 과정에서 서비스 다운이 발생할 수 있는 상황이었습니다."

---

## 4. JVM 메모리 분석 및 최적화 (핵심 스토리)

> **이 스토리가 가장 중요합니다.** 단순 설정 변경이 아니라, 문제를 먼저 발견하고 원인을 분석한 후 수치로 증명한 경험입니다.

### 4-1. 문제 발견: OOM Kill 시한폭탄

기존 JVM 설정을 분석하던 중 심각한 리스크를 발견했다.

**기존 설정**
```
JAVA_TOOL_OPTIONS: -Xms512m -Xmx1536m -XX:MetaspaceSize=128m -XX:MaxMetaspaceSize=256m
limits.memory: 2Gi
```

**메모리 사용량 분석**
```
Heap (Xmx)         = 1,536 Mi
Metaspace (최대)    =   256 Mi
CodeHeap (JIT)     =    70 Mi  ← JIT 컴파일된 기계어 코드 저장
Native/OS 오버헤드 =    50 Mi
─────────────────────────────
예상 최대 사용량    = 1,912 Mi

limits.memory       = 2,048 Mi (2Gi)
여유 = 2,048 - 1,912 = 136 Mi (전체의 6.6%)
```

**결론: 트래픽 스파이크 시 OOM Kill(Exit Code 137) 발생 위험.**
136Mi 여유는 GC가 힙 반환 전에 순간적으로 초과될 수 있는 수준.

추가로 `requests.memory: 768Mi`인데 실제 JVM committed heap을 측정하니 **767Mi** — 여유가 1Mi뿐이었다. 스케줄러가 이 pod를 "가벼운 pod"로 판단해 부하가 몰리는 노드에 배치할 수 있는 상황.

### 4-2. 수정 내용

| 항목 | Before | After | 이유 |
|------|--------|-------|------|
| `-Xmx` | 1536m | 1024m | limits 대비 OOM Kill 여유 확보 |
| `-Xms` | 512m | 256m | 초기 힙 낮춰 시작 시 메모리 절약 |
| `limits.memory` | 2Gi | 1536Mi | 실제 최대 사용량 기반으로 현실화 |
| `requests.memory` | 768Mi | 1Gi | 실제 committed 메모리 반영 |
| `ephemeral-storage` limits | 없음 | 500Mi | DiskPressure 방지용 추가 |
| `+UseContainerSupport` | 없음 | 추가 | cgroup 메모리 제한 인식 명시 |
| GC 로깅 | 없음 | 추가 | `/tmp/gc.log` 로 GC 분석 가능 |

**After 설정**
```
Heap (Xmx)         = 1,024 Mi
Metaspace (최대)    =   256 Mi
CodeHeap (JIT)     =    70 Mi
Native/OS 오버헤드 =    50 Mi
─────────────────────────────
예상 최대 사용량    = 1,400 Mi

limits.memory       = 1,536 Mi
여유 = 1,536 - 1,400 = 136 Mi → 추가로 Xmx 미도달 여유까지 고려하면 실질 300Mi+
```

### 4-3. GC 개선 수치

Prometheus Micrometer를 통해 GC 이벤트를 Before/After 비교:

| 지표 | Before (수 시간 운영) | After (워밍업 후) | 변화 |
|------|----------------------|------------------|------|
| GC 이벤트 수 | 37회 | 5회 | **-86%** |
| GC 총 pause time | 1.296s | 0.368s | **-72%** |
| 평균 pause/회 | 35ms | 74ms | (Full GC → Minor GC로 전환) |

> avg pause가 늘어난 이유: Before는 Full GC(힙 전체 정리, 수백ms)가 섞여 있었고, After는 Minor GC(Young Gen만 정리)만 발생. 전체 GC 부하는 줄었으나 개별 pause 시간은 상대적으로 균일해짐.

### 4-4. 부하 테스트 Before/After

**테스트 조건**: k6, 100 VU, 3분 (ramp-up 30s → 100VU 60s → ramp-down 30s), 별도 EC2 서버에서 실행

> JIT 워밍업 공정성 문제: 첫 번째 After 테스트는 롤링 업데이트 직후 실행 → JIT 미워밍업 상태라 Before보다 느림.
> 30분 이상 pod 가동 후 재측정한 결과를 최종 비교값으로 사용.

| 지표 | Before | After (워밍업) | 개선율 |
|------|--------|----------------|--------|
| avg 응답시간 | 411ms | **189ms** | **-54%** |
| p90 | 1,300ms | **658ms** | **-49%** |
| p95 | 1,720ms | **858ms** | **-50%** |
| max | 5,010ms | **4,210ms** | **-16%** |
| TPS | 91/s | **160/s** | **+76%** |
| 에러율 | 0% | **0%** | - |
| 총 처리 요청 | 16,396 | **28,838** | +76% |

### 4-5. HikariCP Cold Start 분석 (보너스)

최초 요청 시 4.6초 응답시간의 원인 분석:

```
hikaricp_connections_creation_seconds_sum   = 30.445s
hikaricp_connections_creation_seconds_count = 30 (connections)
→ 평균 연결 생성 시간 = 30.445 / 30 = 1.015s/connection
→ minimumIdle = 5 → 첫 요청 시 5개 연결 × ~1s = 약 5초
```

DB 연결 자체가 느린 것이 아니라, Connection Pool 초기화가 최초 요청 시점에 발생하는 구조적 원인.

### 면접 스크립트

> "기존 JVM 설정을 분석하다가 OOM Kill 시한폭탄을 발견했습니다. -Xmx1536m에 Metaspace, CodeHeap, Native 오버헤드를 더하면 예상 최대 사용량이 1,912Mi인데 limits가 2Gi(2,048Mi)라, 여유가 136Mi(6.6%)뿐이었습니다. GC가 힙을 반환하기 전 순간적으로 초과하면 컨테이너가 OOM Kill로 죽는 상황이었습니다."

> "그냥 설정만 바꾸는 게 아니라 수치로 증명하고 싶었습니다. k6로 100 VU 부하 테스트를 Before/After로 실행한 결과, 응답시간 p95 기준 1.72초에서 858ms로 50% 개선, TPS는 91에서 160으로 76% 향상을 확인했습니다. 첫 After 테스트가 Before보다 느렸는데, JIT 워밍업 문제였습니다. 롤링 업데이트 직후 바로 측정했기 때문에 JVM이 아직 cold 상태였던 것이고, 30분 워밍업 후 재측정해서 공정한 비교를 했습니다."

---

## 5. NetworkPolicy Default Deny + Whitelist

### 배경

K8s 기본 상태에서는 모든 pod 간 통신이 허용됨. 보안상 필요한 통신만 명시적으로 허용하는 Zero Trust 네트워크 정책 적용.

### 구현

**1단계: Default Deny (모든 Ingress 차단)**
```yaml
# default-deny-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: klosetlab
spec:
  podSelector: {}          # 네임스페이스 내 모든 pod
  policyTypes: [Ingress]   # Ingress만 차단 (Egress는 허용 유지)
```

**2단계: 필요한 경로만 허용**
```yaml
# allow-from-ingress-nginx.yaml  → 외부 트래픽 허용
# allow-inter-service.yaml       → module-api → fastapi 내부 통신 허용
# allow-egress-external.yaml     → 외부 API 호출 허용
```

### 핵심 포인트

- NetworkPolicy는 **정의만** 한다. 실제 iptables 룰은 CNI 플러그인(Calico)이 각 노드에 적용.
- Flannel처럼 NetworkPolicy를 지원하지 않는 CNI를 사용하면 오브젝트를 만들어도 아무 효과 없음.
- `module-api → fastapi` 허용 정책을 빠뜨리면 AI 기능 전체가 타임아웃 → Default Deny 적용 전에 반드시 통신 경로 전수 확인 필요.

### 면접 스크립트

> "Default Deny를 적용하면서 pod 간 통신 경로를 전부 직접 추적했습니다. module-api가 AI 추천을 위해 fastapi를 내부 호출하는 경로를 빠뜨렸다가 AI 기능이 통째로 막힐 뻔했습니다. NetworkPolicy 자체는 선언적 오브젝트고, 실제 패킷 차단은 Calico가 iptables로 구현합니다. CNI가 NetworkPolicy를 지원하는지 반드시 확인해야 하는 이유입니다."

---

## 6. 장애 대응 경험 3가지

### 6-1. EC2 Impaired 상태 복구

**현상**
- worker2 `NotReady`, SSH 접속 불가

**진단 과정**
```bash
aws ec2 describe-instance-status --instance-id i-xxx
# → InstanceStatus: impaired
# → SystemStatus: impaired
```

**시도 1: reboot → 실패**
reboot 후에도 impaired 상태 유지. 소프트웨어 문제가 아닌 **물리 하드웨어 결함**.

**해결: stop → start**
```bash
aws ec2 stop-instances --instance-ids i-xxx
aws ec2 start-instances --instance-ids i-xxx
# → AWS가 다른 물리 서버로 인스턴스 이전
# → 노드 정상화, kubelet 재기동, Ready 복귀
```

**교훈**: EC2 impaired는 물리 장비 문제 → reboot은 같은 하드웨어를 재사용하므로 의미 없음. stop/start로 하드웨어를 교체해야 함.

---

### 6-2. Git 시크릿 노출 인시던트

**현상**
`.claude/settings.local.json`에 AWS Access Key + GitHub Token이 커밋됨 → `git push` 시 GitHub Secret Scanning이 차단.

```
remote: error: GH013: Repository rule violations found.
remote: - GITHUB SECRET SCANNING: Secrets detected
```

**해결 과정**
```bash
# 1. git-filter-repo로 해당 파일을 전체 히스토리에서 삭제
pip3 install git-filter-repo
git filter-repo --path .claude/settings.local.json --invert-paths --force

# 2. 히스토리 재작성으로 remote 연결이 끊기므로 재설정
git remote add origin https://github.com/...

# 3. 강제 push (히스토리가 달라졌으므로)
git push --force
```

**후속 조치**
- 노출된 AWS 키, GitHub 토큰 즉시 rotate
- `.gitignore`에 IDE/툴 설정 파일 경로 추가

**교훈**: `git commit --amend`나 `git reset`으로는 히스토리에서 파일을 완전히 제거할 수 없다. `git filter-repo`(또는 `BFG Repo Cleaner`)를 사용해야 모든 커밋에서 제거된다. 시크릿은 히스토리에서 지웠어도 노출됐다고 간주하고 반드시 rotate.

---

### 6-3. DiskPressure 인시던트 (분석 + 대응)

**현상**
부하 테스트 + 롤링 업데이트 동시 진행 중, pod 40개 동시 eviction 발생.

**진단**
```bash
kubectl describe node ip-10-0-11-177
# Events:
#   Warning  NodeHasDiskPressure  kubelet  Node status is now: NodeHasDiskPressure
```

**원인 분석**

```
노드 디스크: 8GB EBS (루트 파티션 6.8GB)
사용 중: 5.3GB (79%) → 정상 운영 시 거의 한계

롤링 업데이트 시 동시 발생 이벤트:
  - 새 ReplicaSet pod들이 이미지 pull (이미지 레이어 추가)
  - 이전 ReplicaSet pod들의 writable layer 잔존
  - GC 로그 파일 (/tmp/gc.log, 최대 30MB/pod)
  → 순간 85% 초과 → kubelet이 pod 강제 eviction 시작
```

**기존 노드(worker1)와의 차이**: worker1은 30GB EBS → 같은 상황에서도 여유 충분

**임시 조치**
```bash
# 1. 문제 노드 eviction 방지 (신규 스케줄링 차단)
kubectl cordon ip-10-0-11-177
kubectl cordon ip-10-0-12-34

# 2. Evicted pod 정리
kubectl delete pods -n klosetlab --field-selector=status.phase=Failed
```

**영구 조치 (예정)**
- AWS 콘솔에서 해당 EBS 볼륨 8GB → 30GB resize
- 노드에서 `growpart`, `resize2fs` 실행
- `kubectl uncordon`으로 스케줄링 재개

**이 상황에서도 서비스 유지**
40개 pod eviction 중에도 **k6 에러율 0%** — 다른 노드의 pod 3개가 서비스 지속, PDB가 최소 가용성 보장.

**교훈**: K8s 워커 노드는 운영 중 이미지 레이어, 로그, 임시 파일이 지속적으로 쌓인다. 최소 20GB, 권장 30GB 이상의 루트 디스크 필요. 노드 프로비저닝 시 디스크 크기 표준화가 필수.

---

## 전체 성과 수치 요약

| 항목 | Before | After |
|------|--------|-------|
| 배포 방식 | 수동 kubectl | GitOps (ArgoCD + Helm) |
| 평균 응답시간 | 411ms | **189ms (-54%)** |
| p95 응답시간 | 1,720ms | **858ms (-50%)** |
| TPS | 91/s | **160/s (+76%)** |
| GC 이벤트 수 | 37회/세션 | **5회 (-86%)** |
| GC 총 pause | 1.296s | **0.368s (-72%)** |
| OOM Kill 여유 | 136Mi (6.6%) | **300Mi+ (20%+)** |
| 장애 대응 | 수동 SSH | kubectl 진단 + 자동 복구 |

---

## 면접 한 줄 요약

> "K8s 4노드 클러스터를 직접 구축·운영하면서, JVM 메모리 분석으로 OOM Kill 리스크를 사전 제거하고 부하 테스트로 TPS 76% 향상을 수치로 증명했습니다. 롤링 업데이트 중 DiskPressure로 pod 40개가 동시 eviction되는 상황에서도 PDB 덕분에 에러율 0%를 유지한 실전 운영 경험이 있습니다."

---

## 꼬리질문 한 번에 보기

### K8s 기본 개념

**Q. requests와 limits 차이?**
> requests는 스케줄러가 노드를 선택할 때 기준으로 쓰는 "보장값". limits는 컨테이너가 초과하면 안 되는 "상한값". requests <= limits여야 하고, requests=limits이면 QoS Guaranteed 클래스가 부여돼 eviction 우선순위에서 가장 안전.

**Q. OOM Kill은 누가 해?**
> Linux 커널의 OOM Killer. K8s limits.memory를 초과하면 cgroup이 메모리 할당을 막고, OOM Killer가 해당 프로세스(JVM)를 SIGKILL(Exit Code 137)로 종료. K8s는 이후 CrashLoopBackOff로 재시작.

**Q. HPA가 scale하는 데 얼마나 걸려?**
> 기본 15초마다 메트릭 수집, scale-up은 즉시, scale-down은 5분 대기 후 실행 (flapping 방지). `--horizontal-pod-autoscaler-downscale-stabilization` 으로 조정 가능.

**Q. Rolling Update 중 구버전과 신버전이 동시에 뜨는데 DB 스키마가 다르면?**
> Blue-Green 또는 Canary 배포로 전환 필요. 또는 Backward Compatible 마이그레이션(컬럼 추가만, 삭제는 다음 배포에서) 전략 적용. ArgoCD Rollouts를 쓰면 K8s에서 Blue-Green/Canary를 선언적으로 관리 가능.

### JVM 관련

**Q. UseContainerSupport가 없으면 어떻게 돼?**
> JVM이 cgroup 메모리 제한을 무시하고 EC2 전체 메모리(예: 8GB)를 기준으로 -Xmx를 자동 계산. pod limits가 2Gi여도 JVM이 4GB 힙을 잡으려다 즉시 OOM Kill. Java 10+ / Java 8u191+에서 기본 활성화되지만 명시적으로 추가해 의도를 분명히 함.

**Q. -Xms를 낮게 설정하면 단점은?**
> 초반에 힙이 작아서 Minor GC가 더 자주 발생. 트래픽이 급증하면 JVM이 힙을 Xmx까지 늘리는 과정에서 GC pause가 증가. 안정적인 트래픽이라면 Xms=Xmx로 설정해 힙 사이즈 변동 자체를 없애는 전략도 있음.

**Q. GC 로그를 왜 파일로 남겨?**
> pod 재시작 시 메모리에 있는 로그는 사라짐. `/tmp/gc.log`에 저장하면 pod 살아있는 동안 분석 가능. `filecount=3, filesize=10m`으로 총 30MB 로테이션 → 디스크 무한 증가 방지. 더 나아가면 Fluentd로 GC 로그를 중앙 로그 시스템으로 수집.

### 운영/장애

**Q. kubectl cordon vs drain 차이?**
> cordon은 새 pod 스케줄링만 막음 (기존 pod는 그대로). drain은 기존 pod도 다른 노드로 이전시킴 (PDB 존중). 유지보수 전에는 drain, 일시적 격리에는 cordon.

**Q. EC2 impaired는 어떻게 탐지해?**
> `aws ec2 describe-instance-status`로 InstanceStatus/SystemStatus 확인. 또는 CloudWatch가 자동 감지해 SNS 알림 설정 가능. K8s 레벨에서는 kubelet heartbeat가 끊기면 `NotReady`로 표시, 5분 후 pod eviction 시작.

**Q. ephemeral-storage limits를 추가하면 뭐가 달라지나?**
> limits 없을 때: 노드 전체 디스크가 85%를 넘으면 kubelet이 pod를 우선순위 기반으로 한꺼번에 강제 축출. limits 있을 때: kubelet이 각 pod의 ephemeral storage 사용량을 개별 추적해서, limits(500Mi)를 초과한 pod만 선별 축출 → 정상 pod는 영향 없음. OOM Kill과 동일한 원리로 "개별 컨테이너 단위 관리"가 가능해짐.

**Q. DiskPressure와 OOM Kill의 차이?**
> OOM Kill: 메모리 초과 → 커널 OOM Killer가 해당 프로세스를 SIGKILL (Exit Code 137) → K8s가 컨테이너 재시작. 서비스 순간 중단.
> DiskPressure: 노드 디스크 85% 이상 → kubelet이 pod를 eviction (graceful termination 적용됨) → Deployment가 다른 노드에 새 pod 생성. DiskPressure는 involuntary eviction이라 PDB 보호를 받지 못함. 이 차이 때문에 DiskPressure 상황에서도 PDB와 Anti-Affinity가 결합돼야 서비스 연속성이 보장됨.

**Q. 부하 테스트를 왜 Before/After로 나눠서 했나? 그냥 한 번만 하면 안 돼?**
> 처음에 After 테스트를 롤링 업데이트 직후 바로 실행했더니 Before(p95 1.72s)보다 오히려 느렸음 (p95 1.89s). 원인 분석: JVM JIT 컴파일러는 메서드 호출 횟수가 쌓여야 네이티브 코드로 최적화함. Before pod는 수 시간 운영 중이라 JIT 워밍업 완료 상태, After pod는 롤링 업데이트 직후 cold 상태. 이를 인식하고 30분 이상 워밍업 후 재측정해서 공정한 비교 진행. "왜 처음 After 테스트가 느렸는지"를 분석한 과정 자체가 JVM 동작 이해를 보여줌.

**Q. preferred Pod Anti-Affinity인데 pod 10개, 노드 3개면 어떻게 돼?**
> preferred이므로 hard limit 없음. 스케줄러가 최대한 분산시키되 (각 노드에 3~4개), 수용 불가 노드가 있으면 같은 노드에 중복 배치. `required`였다면 4번째 pod가 "남은 노드 없음"으로 Pending. HPA와 함께 쓸 때 required는 위험 — 스케일 아웃 자체가 막힐 수 있음.

**Q. ArgoCD selfHeal이 뭔가, 언제 문제가 생기나?**
> selfHeal: 클러스터에서 수동으로 변경하면 ArgoCD가 감지해 Git 상태로 자동 복원. 장점은 드리프트 방지. 단점은 긴급 상황에서 `kubectl edit`으로 즉시 수정해도 ArgoCD가 몇 분 내로 되돌림 — 장애 대응 중에 혼선 가능. 이를 막으려면 임시로 ArgoCD sync를 suspend하거나, 변경 내용을 Git에 먼저 push해야 함.

**Q. git filter-repo 이후 credentials를 왜 rotate해야 하나? 이미 히스토리에서 지웠는데?**
> GitHub은 push 전에 Secret Scanning으로 이미 탐지했고, 다른 사람이 `git clone`이나 `git fetch`로 히스토리를 받았을 수도 있음. GitHub 자체 캐시나 Search 인덱스에도 잔존 가능. filter-repo는 "향후 노출"을 막는 것이고, "기존 노출"은 이미 발생한 것으로 간주해야 함. 노출된 키로 무슨 행동이 있었는지 CloudTrail 로그 확인도 필요.
