# 노드 및 Pod 배치 설계

> 워커 노드 4개 확장 시 서비스 특성에 맞는 노드/Pod 배치 전략

---

## 1. 노드 구성

### 인스턴스 스펙

| 노드 | 역할 | 인스턴스 타입 | vCPU | Memory |
|------|------|-------------|------|--------|
| ip-10-0-11-26 | control-plane | t3.medium | 2 | 3.7GB |
| worker1 (ip-10-0-11-192) | app | t3.medium | 2 | 3.7GB |
| worker2 (ip-10-0-12-235) | app | t3.medium | 2 | 3.7GB |
| worker3 (신규) | app | t3.medium | 2 | 3.7GB |
| worker4 (신규) | ai | t3.medium | 2 | 3.7GB |

> K8s 시스템 예약 후 실제 스케줄 가능 자원: CPU ~1900m, Memory ~3200Mi

---

## 2. 노드 역할 분리 설계

```
┌─────────────────────────────────────────────────────────────────┐
│  worker1  (node-role=app)     worker2  (node-role=app)          │
│  ┌──────────────────────┐     ┌──────────────────────┐         │
│  │ module-api Pod       │     │ module-api Pod       │         │
│  │ module-chat Pod      │     │ module-chat Pod      │         │
│  └──────────────────────┘     └──────────────────────┘         │
│                                                                  │
│  worker3  (node-role=app)     worker4  (node-role=ai)           │
│  ┌──────────────────────┐     ┌──────────────────────┐         │
│  │ module-api Pod       │     │ fastapi Pod          │         │
│  │ module-chat Pod      │     │ fastapi Pod          │         │
│  └──────────────────────┘     └──────────────────────┘         │
└─────────────────────────────────────────────────────────────────┘
```

### 역할 분리 이유

| 구분 | 이유 |
|------|------|
| app / ai 분리 | fastapi(AI)는 ML 모델 로딩으로 메모리 사용 패턴이 다름. Java 서비스와 리소스 경합 방지 |
| app 노드 3개 | module-api, module-chat은 HPA로 최대 5개까지 스케일아웃. 3개 노드에 균등 분산 |
| ai 노드 1개 | fastapi는 최대 4개. AI 서비스 독립 격리로 장애 전파 차단 |

---

## 3. 서비스별 Resource 설계

### 설계 기준

- **requests**: 스케줄러가 노드 배치 시 보장하는 최소 자원. 너무 높으면 노드 낭비, 너무 낮으면 다른 Pod에 자원 뺏김
- **limits**: 컨테이너가 사용할 수 있는 최대 자원. 초과 시 CPU throttling / OOM Kill 발생
- **requests ≠ limits**: 자원 효율을 높이되, 버스트 트래픽에 대응 가능하도록 limits에 여유 부여

### module-api (Spring Boot)

```yaml
resources:
  requests:
    cpu: 250m       # 평상시 사용량 기준 (top 측정값: ~62m, 버스트 여유 포함)
    memory: 768Mi   # JVM 힙 512m + Metaspace 128m + OS 여유
  limits:
    cpu: 500m       # requests의 2배 — 요청 급증 시 버스트 허용
    memory: 2Gi     # OOM 방지. JVM JAVA_TOOL_OPTIONS: -Xmx1536m
```

**JVM 힙 설정 배경:**
```
JAVA_TOOL_OPTIONS: -Xms512m -Xmx1536m -XX:MetaspaceSize=128m -XX:MaxMetaspaceSize=256m
```
- limits.memory(2Gi) = JVM heap max(1536m) + Metaspace(256m) + JVM 오버헤드(~200m)
- `limits < Xmx`이면 OOM Kill 발생 → limits를 Xmx보다 반드시 크게 설정

### module-chat (Spring Boot WebSocket)

```yaml
resources:
  requests:
    cpu: 250m
    memory: 512Mi   # WebSocket 서비스 — module-api보다 메모리 사용 적음
  limits:
    cpu: 500m
    memory: 1Gi
```

### fastapi (Python AI)

```yaml
resources:
  requests:
    cpu: 500m       # ML 모델 추론 — Java보다 CPU 집약적
    memory: 1Gi     # ML 모델 로딩 메모리
  limits:
    cpu: 1000m      # 추론 시 CPU 버스트 허용
    memory: 2Gi
```

---

## 4. 노드별 자원 점유율 계산

### app 노드 (worker1~3) — 기본 상태 (replicas: 2)

Pod Anti-Affinity로 2개 Pod이 2개 노드에 분산:

| 항목 | 값 |
|------|---|
| module-api 1개 requests | CPU 250m, Memory 768Mi |
| module-chat 1개 requests | CPU 250m, Memory 512Mi |
| **노드당 합계** | **CPU 500m / 3200Mi 중 500m (26%), Memory 1280Mi (40%)** |

→ **HPA 최대 스케일 시** (module-api 5개, module-chat 5개, 노드 3개):
- 노드당 약 3~4개 Pod → CPU ~900m (47%), Memory ~2000Mi (62%)
- 여전히 한계 이내 — 안정적

### ai 노드 (worker4) — 기본 상태 (replicas: 2)

| 항목 | 값 |
|------|---|
| fastapi 2개 requests | CPU 1000m, Memory 2Gi |
| **노드 점유율** | **CPU 1000m / 1900m (52%), Memory 2Gi / 3.2Gi (62%)** |

→ **HPA 최대 스케일 시** (fastapi 4개):
- CPU 2000m → 노드 한계 초과 가능 → limits 기준으로는 throttling 발생
- **의도적 설계**: AI 추론은 짧은 순간 CPU 집약 후 idle → throttling 허용 범위

---

## 5. Pod 분산 전략

### 노드 역할 분리 동작 원리

#### 1단계: 노드에 라벨 붙이기

K8s 노드는 그냥 서버야. 거기에 **라벨(key=value)**을 붙이면 스케줄러가 인식할 수 있어.
라벨 자체는 아무 기능 없음. 그냥 태그. **"이 라벨을 보고 어떻게 행동할지"는 Pod 설정에서 정의함.**

```bash
kubectl label node ip-10-0-11-192 node-role=app
kubectl label node ip-10-0-12-235 node-role=app
kubectl label node worker3        node-role=app
kubectl label node worker4        node-role=ai
```

확인:
```bash
kubectl get nodes --show-labels | grep node-role
# ip-10-0-11-192  Ready  ...  node-role=app
# ip-10-0-12-235  Ready  ...  node-role=app
# worker4         Ready  ...  node-role=ai
```

#### 2단계: Pod이 특정 라벨의 노드를 선호하도록 설정

fastapi deployment에 추가:

```yaml
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      preference:
        matchExpressions:
        - key: node-role
          operator: In
          values: ["ai"]
```

읽는 방법:
```
새 Pod 스케줄할 때 (DuringScheduling)
→ node-role=ai 라벨 달린 노드를 weight 100으로 선호해
→ 없으면 그냥 아무 노드에 올라가도 돼 (preferred니까)

이미 실행 중인 Pod은 건드리지 않음 (IgnoredDuringExecution)
```

#### 3단계: 스케줄러가 실제로 하는 일

Pod 하나 생성 요청이 들어오면 K8s 스케줄러가 두 단계를 거침:

```
1. Filtering: 올라갈 수 없는 노드 제거
   - 자원(CPU/Memory) 부족한 노드 제거
   - required NodeAffinity 불만족 노드 제거 (preferred는 이 단계에서 제거 안 됨)

2. Scoring: 남은 노드들 점수 매기기
   - preferred NodeAffinity 만족하면 +100점
   - podAntiAffinity 만족하면 +100점 (같은 Pod 없는 노드)
   - 자원 여유 있는 노드 추가 점수

3. 최고 점수 노드에 배치
```

fastapi Pod 2개 생성 시 점수 계산 예시:
```
1번 Pod:
  worker4 (node-role=ai, fastapi 없음): nodeAffinity +100 = 100점  ← 선택
  worker1,2,3 (node-role=app):          0점

2번 Pod:
  worker4 (node-role=ai, fastapi 1개 있음): nodeAffinity +100, antiAffinity 0 = 100점
  worker1   (node-role=app, fastapi 없음):  nodeAffinity 0, antiAffinity +100 = 100점
  → 동점 → 자원 여유 기준으로 결정
  → 결과: worker4에 몰리거나 다른 노드로 분산 (preferred라 둘 다 가능)
```

### Node Affinity (Soft)

`preferred` 방식으로 강제가 아닌 선호도 설정:

```yaml
affinity:
  nodeAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      preference:
        matchExpressions:
        - key: node-role
          operator: In
          values: ["app"]   # fastapi는 ["ai"]
```

**`required` 대신 `preferred` 선택 이유:**
- `required`: ai 노드 장애 시 fastapi Pod이 Pending 상태 유지 → 서비스 중단
- `preferred`: ai 노드 장애 시 다른 노드에 폴백 스케줄링 → 서비스 유지

### Pod Anti-Affinity (Soft)

같은 서비스의 Pod이 동일 노드에 몰리지 않도록:

```yaml
podAntiAffinity:
  preferredDuringSchedulingIgnoredDuringExecution:
  - weight: 100
    podAffinityTerm:
      labelSelector:
        matchLabels:
          app: module-api
      topologyKey: kubernetes.io/hostname
```

**효과:** replicas: 2 → 서로 다른 2개 노드에 1개씩 배치. 노드 1개 장애 시 나머지 1개로 서비스 지속

#### required vs preferred — Pod 수가 노드 수를 초과할 때

**`required` (하드) 사용 시 — Pod 10개, 노드 3개:**
```
Node1: Pod1  ← OK
Node2: Pod2  ← OK
Node3: Pod3  ← OK
Pod4~10: 모든 노드에 이미 같은 Pod 존재 → 조건 위반 → Pending
```
→ **3개만 뜨고 나머지 7개는 영영 Pending.** 노드 수가 최대 replicas의 상한선이 됨.

**`preferred` (소프트) 사용 시 — Pod 10개, 노드 3개:**
```
Pod1 → Node1 배치 (같은 Pod 없음, +100점)
Pod2 → Node2 배치 (+100점)
Pod3 → Node3 배치 (+100점)
Pod4 → Node1,2,3 모두 동점(0점) → 자원 여유 있는 노드에 배치
Pod5~10 → 균등 분산
```
결과:
```
Node1: Pod1, Pod4, Pod7, Pod10
Node2: Pod2, Pod5, Pod8
Node3: Pod3, Pod6, Pod9
```
→ **10개 전부 뜸.** 가능하면 분산하고, 불가능하면 같이 올라감.

**이 프로젝트에서 `preferred` 선택 이유:**
HPA로 module-api가 최대 5개까지 스케일아웃되는데 app 노드가 3개.
`required`였다면 3개 초과 스케일아웃이 불가능 → HPA 무력화.
`preferred`이기 때문에 5개 전부 뜨면서 가능한 범위 내에서 분산 배치됨.

---

## 6. PDB (Pod Disruption Budget)

노드 drain(유지보수) 또는 롤링 업데이트 중 최소 Pod 수 보장:

```yaml
spec:
  minAvailable: 1   # 최소 1개는 항상 Running 보장
```

**시나리오:**
```
replicas: 2, minAvailable: 1

노드 drain 시도 →
  K8s: "Pod 1개 evict 가능? minAvailable(1) 충족하면 OK"
  → Pod 1개 종료, 나머지 1개로 서비스 지속
  → 새 노드에 Pod 스케줄 완료 후 다음 drain 허용
```

---

## 7. HPA (Horizontal Pod Autoscaler)

metrics-server에서 CPU 사용률 수집 → 70% 초과 시 자동 스케일아웃:

| 서비스 | min | max | 기준 |
|--------|-----|-----|------|
| module-api | 2 | 5 | CPU 70% |
| module-chat | 2 | 5 | CPU 70% |
| fastapi | 2 | 4 | CPU 70% |

**ArgoCD ignoreDifferences 설정 이유:**
HPA가 런타임에 `spec.replicas`를 변경하면, ArgoCD selfHeal이 Git 값(replicas: 2)으로 강제 복원 → 스케일아웃 무력화.
`ignoreDifferences`로 `spec.replicas` 필드를 ArgoCD 감시에서 제외:

```yaml
ignoreDifferences:
- group: apps
  kind: Deployment
  jsonPointers:
  - /spec/replicas
```
