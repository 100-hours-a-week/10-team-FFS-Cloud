# Calico NetworkPolicy 설계

> Zero Trust 네트워크 정책 — 모든 트래픽 기본 차단 후 필요한 경로만 명시적 허용

---

## 1. 배경 — Flannel에서 Calico로 전환한 이유

Flannel은 Pod 간 오버레이 네트워크만 제공하고 **NetworkPolicy를 지원하지 않음.**
NetworkPolicy 파일을 apply해도 Flannel은 무시 → 실제 트래픽 제어 불가.

Calico로 CNI를 교체하면:
- IPIP 터널링으로 Pod 간 네트워크 제공 (Flannel과 동일 역할)
- `calico-node`가 NetworkPolicy를 Watch → **iptables 규칙 자동 생성/수정**
- 커널 레벨에서 실제 패킷 차단/허용 실행

---

## 2. 설계 원칙 — Default Deny + Whitelist

### Allow 기반 (위험)
```
기본: 모든 트래픽 허용
→ 새 서비스 추가 시 실수로 과도한 권한 열릴 수 있음
→ 보안 누락을 발견하기 어려움
```

### Deny 기반 (채택) ✅
```
기본: 모든 트래픽 차단
→ 명시적으로 허용하지 않으면 무조건 차단
→ 새 서비스 추가 시 필요한 정책을 의식적으로 추가해야 함
→ 보안 누락이 서비스 장애로 즉시 드러남
```

---

## 3. 구성한 정책 4개

```
v3/k8s/network-policy/
├── default-deny-ingress.yaml       ① 모든 인바운드 기본 차단
├── allow-from-ingress-nginx.yaml   ② nginx-ingress → 앱 허용
├── allow-inter-service.yaml        ③ module-api → fastapi 허용
└── allow-egress-external.yaml      ④ VPC 내부 + 인터넷 아웃바운드 허용
```

---

## 4. 정책별 상세

### ① default-deny-ingress.yaml

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: klosetlab
spec:
  podSelector: {}   # {} = klosetlab 네임스페이스 전체 Pod에 적용
  policyTypes:
  - Ingress
  # ingress 규칙 없음 = 모든 인바운드 차단
```

`podSelector: {}`가 핵심. 비어있는 selector = 네임스페이스 **전체** Pod에 적용.

적용 결과:
```
외부     → module-api  ❌ 차단
외부     → module-chat ❌ 차단
외부     → fastapi     ❌ 차단
Pod      → Pod         ❌ 차단 (같은 네임스페이스 포함)
```

---

### ② allow-from-ingress-nginx.yaml

```yaml
spec:
  podSelector: {}           # klosetlab 전체 Pod에 적용
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx
```

`ingress-nginx` 네임스페이스에서 오는 트래픽만 허용.
외부 요청은 반드시 nginx-ingress를 통해서만 진입 가능 → **외부 진입점 단일화.**

```
인터넷 → Bastion → nginx-ingress(ingress-nginx ns) → 앱 Pod ✅
인터넷 → 앱 Pod 직접 접근 시도                              ❌ 차단
```

---

### ③ allow-inter-service.yaml

```yaml
spec:
  podSelector:
    matchLabels:
      app: fastapi          # fastapi Pod에 적용
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: module-api   # module-api에서 오는 트래픽만 허용
```

**이 정책이 필요한 이유:**
Default Deny 적용 후 module-api → fastapi 직접 호출이 차단됨.
module-api가 AI 기능(옷 분석 등)을 사용하려면 fastapi를 직접 호출해야 하므로 별도 허용 정책 추가.

- `app: module-api` → `app: fastapi` ✅ 허용
- `app: module-chat` → `app: fastapi` ❌ 차단 (module-chat은 fastapi 호출 불필요)

namespaceSelector가 아닌 **podSelector**로 허용 범위를 Pod label 단위까지 최소화.

---

### ④ allow-egress-external.yaml

```yaml
spec:
  podSelector: {}
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 10.0.0.0/16       # VPC 내부 (RDS, Redis, Kafka, Qdrant)
  - to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
        - 10.0.0.0/8            # 인터넷 허용 (ECR pull, 카카오 OAuth 등)
  - ports:
    - port: 53
      protocol: UDP             # DNS 허용 (없으면 도메인 조회 불가)
    - port: 53
      protocol: TCP
```

**DNS 포트 53 명시 이유:**
누락 시 Pod 내부에서 도메인 조회가 불가능해 ECR 이미지 pull, 외부 API 호출, DB 연결이 전부 실패함.

**Egress를 전체 인터넷 허용으로 설정한 이유:**
카카오 OAuth, ECR, 외부 AI API 등 다양한 외부 엔드포인트를 사용하므로 포트/IP 단위 제한이 현실적으로 어려움.
단, VPC 내부 사설 IP(10.0.0.0/8)는 별도 규칙으로 명확히 분리.

---

## 5. 전체 트래픽 흐름

```
[인터넷]
    │
    ▼ (허용)
[nginx-ingress]                    ← 외부 트래픽 단일 진입점
    │
    ▼ ② allow-from-ingress-nginx
┌───────────────────────────────┐
│  module-api    module-chat    │  klosetlab namespace
│      │                        │
│      │ ③ allow-inter-service  │
│      ▼                        │
│   fastapi                     │
└───────────────────────────────┘
    │
    ▼ ④ allow-egress-external
[RDS / Redis / Kafka / 카카오 API / ECR]


Pod → Pod (허용 규칙 없는 경우)  ❌ 차단
외부 → Pod (nginx 우회 시도)     ❌ 차단
module-chat → fastapi 직접 호출  ❌ 차단
```

---

## 6. 동작 원리 — Calico가 iptables로 변환

```
[kubectl apply NetworkPolicy]
          ↓
[K8s API Server에 오브젝트 저장]
          ↓
[Calico가 Watch로 변경 감지]
          ↓
[각 노드의 calico-node Pod이 iptables 규칙 생성]
          ↓
[Linux 커널이 패킷 단위로 차단/허용 실행]
```

Pod IP가 바뀌어도 Calico가 실시간으로 감지해 iptables를 자동 업데이트.
`kubectl get pods -o wide`로 IP가 달라져도 정책은 **Pod label 기준**으로 적용되므로 항상 유효.

---

## 7. 면접 예상 질문 & 답변

**Q. NetworkPolicy가 실제로 어떻게 동작하나요?**
> K8s NetworkPolicy는 선언적 규칙이고, 실제 패킷 차단은 CNI인 Calico가 담당합니다.
> Calico의 calico-node가 API Server를 Watch하다가 NetworkPolicy 변경을 감지하면, 각 노드에서 iptables 규칙을 자동으로 생성/수정합니다.
> Flannel 같은 CNI는 NetworkPolicy를 지원하지 않아 Calico로 교체했습니다.

**Q. Default Deny를 쓰면 기존 서비스가 다 끊기지 않나요?**
> 맞습니다. Default Deny 적용 후 module-api → fastapi 서비스 간 통신이 차단되는 문제를 발견했습니다.
> ingress-nginx 허용 정책만으로는 서비스 간 직접 호출이 막혀, allow-inter-service 정책을 별도로 추가해 module-api가 fastapi AI 기능을 호출할 수 있도록 했습니다.

**Q. Egress는 왜 전체 인터넷을 허용했나요?**
> 카카오 OAuth, ECR 이미지 pull, 외부 AI API 등 다양한 외부 엔드포인트가 있어 포트/IP 단위 제한이 현실적으로 어렵습니다.
> 대신 VPC 내부 사설 IP(10.0.0.0/8)는 별도 규칙으로 처리해 내부 서비스 접근을 명확히 분리했습니다.
> 실무에서는 FQDN 기반 Egress 정책(Calico Enterprise)으로 더 세밀하게 제어할 수 있습니다.

**Q. NetworkPolicy와 AWS Security Group의 차이는 무엇인가요?**
> Security Group은 EC2 인스턴스(노드) 레벨에서 동작하고, NetworkPolicy는 Pod 레벨에서 동작합니다.
> 같은 노드에 있는 Pod A와 Pod B 사이의 트래픽은 Security Group으로 제어할 수 없지만, NetworkPolicy로는 제어 가능합니다.
> 두 레이어를 함께 사용하면 노드 레벨과 Pod 레벨 모두 보안이 적용된 이중 방어 구조가 됩니다.
