# v2-Staging 현재 인프라 구조 (AS-IS)

- **기준일**: 2026-03-04 (AWS 리소스 직접 확인)
- **프로젝트**: `klosetlab-staging-v2`
- **리전**: `ap-northeast-2` (서울)
- **도메인**: `staging-api.klosetlab.site`

---

## 1. 네트워크 (VPC: `10.0.0.0/16`)

| 구분 | 이름 | AZ | CIDR | Subnet ID |
|------|------|----|------|-----------|
| Public | public-a | ap-northeast-2a | 10.0.1.0/24 | subnet-06fbf10195b757563 |
| Public | public-c | ap-northeast-2c | 10.0.2.0/24 | subnet-0d7b8a172debfeac5 |
| Private App | private-app-a | ap-northeast-2a | 10.0.11.0/24 | subnet-08855d5cd95577c14 |
| Private App | private-app-c | ap-northeast-2c | 10.0.12.0/24 | subnet-01586fcef1ca7b23e |
| Private Data | private-data-a | ap-northeast-2a | 10.0.21.0/24 | subnet-0a1c0f78e3b9a193f |
| Private Data | private-data-c | ap-northeast-2c | 10.0.22.0/24 | - |

- NAT Gateway: 단일 AZ (ap-northeast-2a)
- Internet Gateway: 있음
- Private Data Subnet: 인터넷 라우팅 없음 (VPC 내부 통신만)

---

## 2. 로드 밸런서

### ALB 1 — 외부 (Internet-facing)

**`klosetlab-staging-v2-alb`**

- 위치: Public Subnet a + c
- DNS: `klosetlab-staging-v2-alb-511178600.ap-northeast-2.elb.amazonaws.com`
- Route53: `staging-api.klosetlab.site` → A alias

| 리스너 | 포트 | 동작 |
|--------|------|------|
| HTTP | 80 | HTTPS 301 리다이렉트 |
| HTTPS | 443 | TLS 1.3 (ELBSecurityPolicy-TLS13-1-2-2021-06), ACM 인증서 |

**HTTPS 443 라우팅 규칙 (우선순위 순)**:

| 우선순위 | 경로 패턴 | 대상 타겟 그룹 | 포트 | Health Check |
|---------|-----------|--------------|------|-------------|
| 100 | `/ws*` | chat-tg | 8081 | `/actuator/health` |
| 200 | `/api/v2/chat/*` | chat-tg | 8081 | `/actuator/health` |
| 300 | `/api/*` | app-tg | 8080 | `/actuator/health` |
| default | 나머지 전체 | app-tg | 8080 | `/actuator/health` |

### ALB 2 — 내부 (Internal)

**`klosetlab-staging-v2-fastapi-alb`**

- 위치: Private App Subnet a + c (인터넷 미노출)
- HTTP 80 → fastapi-tg (포트 8000, Health: `/health`)
- App 또는 Chat 서버에서 AI 서비스 호출 시 이 ALB를 통해 접근

---

## 3. 애플리케이션 서버 (ASG + EC2)

EC2 부팅 시 AWS SSM Parameter Store에서 설정값 로드 → ECR에서 이미지 pull → docker-compose 실행.

| 서비스 | ASG 이름 | 인스턴스 | Private IP | 서브넷 | Min/Max/Desired |
|--------|---------|---------|-----------|--------|----------------|
| **App** (Spring API) | klosetlab-staging-v2-app-asg-* | t3.medium | 10.0.11.34 | Private App a | 1 / 2 / 1 |
| **Chat** (Spring WebSocket) | klosetlab-staging-v2-chat-asg-* | t3.medium | 10.0.12.252 | Private App c | 1 / 2 / 1 |
| **AI** (FastAPI) | klosetlab-staging-v2-ai-asg-* | t3.medium | 10.0.12.20 | Private App c | 1 / 2 / 1 |

> Terraform 코드에는 t3.small로 정의되어 있으나, 실제 실행 중인 인스턴스는 **t3.medium**.
> ASG 이름에 타임스탬프 포함 (배포 시마다 갱신됨).

---

## 4. 데이터 레이어

### AWS 관리형

| 서비스 | 종류 | 인스턴스 | 스토리지 | DB명 | 포트 | 엔드포인트 |
|--------|------|---------|---------|------|------|---------|
| **RDS** | MySQL 8.0.44 | db.t3.micro | 20GB gp3 (최대 100GB auto-scale) | klosetlabdb | 3306 | klosetlab-staging-v2-mysql.cx828ko4aocb.ap-northeast-2.rds.amazonaws.com |

- Multi-AZ: 비활성화 / charset: utf8mb4 / 접근: App, Chat, Bastion

### 자체 관리 EC2 — Terraform 관리 (Private Data Subnet a, ap-northeast-2a)

| 서비스 | 버전 | 인스턴스 | Private IP | 루트 EBS | 데이터 EBS | 마운트 경로 | 포트 | 접근 허용 |
|--------|------|---------|-----------|---------|-----------|---------|------|---------|
| **MongoDB** | 7.0 | t3.small | 10.0.21.75 | 8GB gp3 (암호화) | 20GB gp3 `/dev/xvdf` (암호화) | `/data/mongodb` | 27017 | Chat, Bastion |
| **Redis (main)** | - | t3.small | 10.0.21.116 | 8GB gp3 (암호화) | 20GB gp3 `/dev/xvdf` (암호화) | `/data/redis` | 6379 | App, Chat, Bastion |
| **Qdrant** (벡터 DB) | - | t3.small | 10.0.21.235 | 8GB gp3 (암호화) | 20GB gp3 `/dev/xvdf` (암호화) | `/data/qdrant` | 6333 | AI, Bastion |

### 자체 관리 EC2 — 수동 프로비저닝 (Private Data Subnet a)

| 서비스 | 인스턴스 | Private IP | 루트 EBS | 데이터 EBS | 포트 | 접근 허용 |
|--------|---------|-----------|---------|---------|------|---------|
| **Redis (fastapi)** | t3.small | 10.0.21.247 | 28GB gp3 **(암호화 없음)** | 없음 | 6379 | AI, Bastion |

### 자체 관리 EC2 — 수동 프로비저닝 (Private App Subnet a)

| 서비스 | 인스턴스 | Private IP | 루트 EBS | 데이터 EBS | 포트 | 접근 허용 |
|--------|---------|-----------|---------|---------|------|---------|
| **Kafka** | t3.small | 10.0.11.100 | 28GB gp3 **(암호화 없음)** | 없음 | 9092·29092 (broker), 8989 (UI) | App·AI: 9092/29092 / Bastion: 8989 |

> Kafka는 Docker 컨테이너로 실행 추정 (9092: 내부, 29092: 컨테이너 외부 포트).
> 별도 데이터 EBS 없이 루트 볼륨에 데이터 저장 중.

---

## 5. 접근 관리

| 컴포넌트 | 인스턴스 | Private IP | 공인 IP | 서브넷 |
|---------|---------|-----------|--------|--------|
| **Bastion Host** | t3.micro | 10.0.1.141 | 3.37.22.178 (Elastic IP) | Public a |

---

## 6. 이미지 레지스트리 (ECR)

| 레포지토리 | 태그 정책 | Push 스캔 |
|----------|---------|---------|
| `klosetlab-staging-v2-app` | MUTABLE | 활성화 |
| `klosetlab-staging-v2-chat` | MUTABLE | 활성화 |
| `klosetlab-staging-v2-fastapi` | MUTABLE | 활성화 |

---

## 7. 스토리지 (S3 + CloudFront)

| 버킷 | 용도 |
|------|------|
| `klosetlab-staging-v2-frontend` | 프론트엔드 정적 파일 |
| `klosetlab-staging-storage-12191e87` | 앱 이미지 업로드 (presigned URL, v1·v2 공유) |

**CloudFront**:
- Distribution ID: `E1QRLP7WRICUXC`
- CDN 도메인: `d33bnagyzgkisg.cloudfront.net`
- Origin: `klosetlab-staging-v2-frontend.s3.ap-northeast-2.amazonaws.com`
- 상태: Deployed / SPA 라우팅 (404·403 → index.html)

---

## 8. IAM

EC2 Instance Profile 권한:
- ECR: 이미지 pull (`GetAuthorizationToken`, `BatchGetImage` 등)
- S3 Storage 버킷: 읽기·쓰기·삭제 (presigned URL용)
- CloudWatch Logs: 로그 생성·스트림 쓰기

---

## 9. Secret 관리

- **AWS SSM Parameter Store** 사용
- EC2 부팅 시 SSM에서 설정값을 직접 로드

---

## 10. 전체 구조 요약 (트래픽 흐름)

```
인터넷
  │
  ▼
External ALB (staging-api.klosetlab.site)
  ├─ /ws*              → Chat  (8081, t3.medium, Private App c)
  ├─ /api/v2/chat/*    → Chat  (8081, t3.medium, Private App c)
  └─ /api/* (default)  → App   (8080, t3.medium, Private App a)

Internal ALB (내부 전용)
  └─ HTTP 80           → AI    (8000, t3.medium, Private App c)

App  ──→ RDS MySQL   3306  (db.t3.micro,  Private Data a)
App  ──→ Redis-main  6379  (t3.small,     Private Data a)
App  ──→ Kafka       9092  (t3.small,     Private App  a)

Chat ──→ RDS MySQL   3306  (db.t3.micro,  Private Data a)
Chat ──→ MongoDB     27017 (t3.small,     Private Data a)
Chat ──→ Redis-main  6379  (t3.small,     Private Data a)
Chat ──→ Kafka       9092  (t3.small,     Private App  a)

AI   ──→ Qdrant      6333  (t3.small,     Private Data a)
AI   ──→ Redis-fastapi 6379 (t3.small,    Private Data a)
AI   ──→ Kafka       9092  (t3.small,     Private App  a)

Bastion (3.37.22.178) ──→ 전체 Private 인스턴스 SSH 접근
```

---

## 11. K8s 전환 시 주요 고려사항


| 항목 | 현황 (AS-IS) | 전환 방향 (TO-BE) |
|------|------------|-----------------|
| ASG (App, Chat, AI) | EC2 + docker-compose | Deployment + HPA |
| External ALB | path-based routing | Ingress (AWS Load Balancer Controller) |
| Internal ALB (AI) | internal ALB | ClusterIP Service 또는 Internal Ingress |
| RDS MySQL | AWS 관리형 | 변경 없이 유지 |
| MongoDB, Redis(x2), Qdrant | EC2 자체 관리, EBS 마운트 | StatefulSet + PVC 또는 관리형 서비스 검토 |
| Kafka | EC2 수동, 데이터 EBS 없음 | StatefulSet + PVC 또는 MSK 검토 |
| Secret 관리 | AWS SSM Parameter Store | ExternalSecrets Operator로 SSM → K8s Secret 동기화 |
| 이미지 레지스트리 | ECR | 변경 없이 유지 (EKS Node IAM) |
| 프론트엔드 | S3 + CloudFront | 변경 없이 유지 |
