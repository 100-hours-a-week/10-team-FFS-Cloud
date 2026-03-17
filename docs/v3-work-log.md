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
