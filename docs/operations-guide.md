# v3 인프라 운영 가이드

> 클러스터 상태 확인, 배포, 장애 대응 등 일상적인 운영 작업 명령어 모음

---

## 0. 기본 접속 방법

### 마스터 노드 SSH (모든 kubectl 명령은 여기서 실행)
```bash
ssh -i ~/.ssh/klosetlab-key.pem -J ubuntu@3.38.20.22 ubuntu@10.0.11.26
```

### 바스티온 SSH
```bash
ssh -i ~/.ssh/klosetlab-key.pem ubuntu@3.38.20.22
```

### 인프라 서비스 서버 SSH (바스티온 경유)
```bash
# Kafka
ssh -i ~/.ssh/klosetlab-key.pem -J ubuntu@3.38.20.22 ubuntu@10.0.21.135

# Redis
ssh -i ~/.ssh/klosetlab-key.pem -J ubuntu@3.38.20.22 ubuntu@10.0.21.86

# MongoDB
ssh -i ~/.ssh/klosetlab-key.pem -J ubuntu@3.38.20.22 ubuntu@10.0.21.94

# Qdrant
ssh -i ~/.ssh/klosetlab-key.pem -J ubuntu@3.38.20.22 ubuntu@10.0.21.117
```

---

## 1. 전체 상태 한눈에 확인

```bash
# Pod 상태 (가장 자주 쓸 명령어)
kubectl get pods -n klosetlab

# ArgoCD 앱 상태
kubectl get applications -n argocd

# TLS 인증서 상태
kubectl get certificate -n klosetlab

# 서비스 목록
kubectl get svc -n klosetlab

# 인그레스 목록
kubectl get ingress -n klosetlab

# 노드 상태
kubectl get nodes
```

### 정상 상태 예시
```
NAME                      READY   STATUS    RESTARTS   AGE
fastapi-xxx               1/1     Running   0          1h
fastapi-xxx               1/1     Running   0          1h
module-api-xxx            1/1     Running   0          1h
module-api-xxx            1/1     Running   0          1h
module-chat-xxx           1/1     Running   0          1h
module-chat-xxx           1/1     Running   0          1h
```

---

## 2. 서비스 엔드포인트 접근 확인

```bash
# module-api 헬스체크
curl -sk https://v3.klosetlab.site/api/actuator/health
# 정상: {"status":"UP"} 또는 401 (인증 필요)

# fastapi 헬스체크
curl -sk https://v3.klosetlab.site/ai/health
# 정상: {"status":"healthy","services":{"qdrant":"connected","redis":"connected","kafka":"connected"}}

# module-chat WebSocket 연결 테스트 (HTTP upgrade)
curl -sk -I https://v3.klosetlab.site/ws
```

---

## 3. Pod 로그 확인

```bash
# 특정 Pod 로그 (최근 100줄)
kubectl logs <pod-name> -n klosetlab --tail=100

# 실시간 로그 스트리밍
kubectl logs <pod-name> -n klosetlab -f

# 이전 컨테이너 로그 (재시작 전 로그)
kubectl logs <pod-name> -n klosetlab --previous

# 레이블로 여러 Pod 로그 동시 확인
kubectl logs -l app=module-api -n klosetlab --tail=50
kubectl logs -l app=fastapi -n klosetlab --tail=50
kubectl logs -l app=module-chat -n klosetlab --tail=50
```

---

## 4. 배포 (GitHub Actions 자동 배포)

### 자동 배포 트리거
각 앱 레포의 `main` 브랜치에 push하면 자동으로 배포됩니다.

```
BE 레포 push → GitHub Actions 빌드 → ECR push → infra repo 이미지 태그 업데이트
                                                         ↓
                                              ArgoCD 감지 → K8s Rolling Update
```

### 배포 상태 확인
```bash
# ArgoCD 앱 상태 확인
kubectl get applications -n argocd

# Rolling Update 진행 상황 확인
kubectl rollout status deployment/module-api -n klosetlab
kubectl rollout status deployment/fastapi -n klosetlab
kubectl rollout status deployment/module-chat -n klosetlab
```

### 수동 배포 (ArgoCD 강제 sync)
```bash
# ArgoCD가 자동으로 감지 못할 때
kubectl patch application module-api -n argocd \
  --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'
```

---

## 5. 롤백

```bash
# 직전 버전으로 롤백
kubectl rollout undo deployment/module-api -n klosetlab

# 특정 revision으로 롤백
kubectl rollout history deployment/module-api -n klosetlab   # 이력 확인
kubectl rollout undo deployment/module-api -n klosetlab --to-revision=3

# 롤백 완료 확인
kubectl rollout status deployment/module-api -n klosetlab
```

> **주의**: 롤백 후 ArgoCD가 다시 Git 상태(최신 이미지)로 되돌릴 수 있습니다. 영구 롤백이 필요하면 infra repo의 deployment.yaml 이미지 태그를 직접 수정해야 합니다.

---

## 6. Pod 재시작

```bash
# 특정 서비스 전체 Pod 재시작 (무중단)
kubectl rollout restart deployment/module-api -n klosetlab
kubectl rollout restart deployment/module-chat -n klosetlab
kubectl rollout restart deployment/fastapi -n klosetlab
```

---

## 7. Pod 상태 이상 시 대처

### ImagePullBackOff
ECR 토큰이 만료됐을 때 발생합니다.

```bash
# 1. ECR 토큰 수동 갱신
AWS_ACCESS_KEY_ID=<key> AWS_SECRET_ACCESS_KEY=<secret> \
aws ecr get-login-password --region ap-northeast-2 | \
kubectl create secret docker-registry ecr-registry-secret \
  --docker-server=862012315401.dkr.ecr.ap-northeast-2.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(cat) \
  --namespace=klosetlab \
  --dry-run=client -o yaml | kubectl apply -f -

# 2. Pod 재시작
kubectl rollout restart deployment/module-api -n klosetlab
```

### CrashLoopBackOff
Pod가 반복 재시작 중입니다. 로그로 원인 파악:

```bash
# 이전 컨테이너 로그에서 크래시 직전 에러 확인
kubectl logs <pod-name> -n klosetlab --previous | tail -50

# Pod 이벤트 확인 (OOM Kill, Probe 실패 등)
kubectl describe pod <pod-name> -n klosetlab | grep -A 20 Events
```

**주요 원인별 대처**

| Exit Code | 원인 | 대처 |
|-----------|------|------|
| 137 | OOM Kill (메모리 초과) | JAVA_TOOL_OPTIONS 힙 크기 줄이기 또는 limits 증가 |
| 1 | 앱 시작 오류 | 로그에서 에러 메세지 확인 (DB 연결 실패, 환경변수 누락 등) |
| 143 | SIGTERM (정상 종료 신호) | 일시적, 계속되면 로그 확인 |

### OOMKilled 확인
```bash
kubectl describe pod <pod-name> -n klosetlab | grep -i "oom\|exit code\|last state"
```

### Pending (스케줄링 안 됨)
```bash
kubectl describe pod <pod-name> -n klosetlab | grep -A 5 Events
# 노드 리소스 부족이면: kubectl describe nodes | grep -A 5 "Allocated resources"
```

---

## 8. Secret (환경변수) 수정

```bash
# 현재 Secret 내용 확인
kubectl get secret module-api-secret -n klosetlab -o jsonpath='{.data}' \
  | python3 -c "import sys,json,base64; d=json.load(sys.stdin); [print(k,'=',base64.b64decode(v).decode()) for k,v in d.items()]"

# 특정 키 값 수정
kubectl patch secret module-api-secret -n klosetlab \
  --type='json' \
  -p='[{"op":"replace","path":"/data/SOME_KEY","value":"'$(echo -n "new_value" | base64)'"}]'

# Secret 전체 재생성
kubectl delete secret module-api-secret -n klosetlab
kubectl create secret generic module-api-secret \
  --from-literal=KEY1=value1 \
  --from-literal=KEY2=value2 \
  --namespace=klosetlab

# Secret 변경 후 반드시 Pod 재시작
kubectl rollout restart deployment/module-api -n klosetlab
```

---

## 9. Kafka 관리

### Kafka 서버 접속
```bash
ssh -i ~/.ssh/klosetlab-key.pem -J ubuntu@3.38.20.22 ubuntu@10.0.21.135
```

### Kafka 컨테이너 상태 확인
```bash
sudo docker compose ps
sudo docker logs kafka --tail=50
```

### Kafka 재시작
```bash
cd ~ && sudo docker compose restart kafka
```

### Topic 목록 확인
```bash
sudo docker exec kafka /opt/kafka/bin/kafka-topics.sh \
  --list --bootstrap-server localhost:9092
```

### Topic 상세 확인 (파티션, 리더 등)
```bash
sudo docker exec kafka /opt/kafka/bin/kafka-topics.sh \
  --describe --bootstrap-server localhost:9092 \
  --topic ai.clothes.analyze.result
```

### Consumer Group 상태 확인 (메세지 지연 확인)
```bash
sudo docker exec kafka /opt/kafka/bin/kafka-consumer-groups.sh \
  --bootstrap-server localhost:9092 \
  --describe --group ai_analyze_result_worker_group
```

### Kafka UI 접속
Kafka 인스턴스가 보안 그룹에서 8989 포트가 열려 있으면:
```
http://10.0.21.135:8989
```
(VPN 또는 바스티온 터널 필요)

---

## 10. TLS 인증서 관리

### 인증서 상태 확인
```bash
kubectl get certificate -n klosetlab
# READY: True 이면 정상

kubectl describe certificate klosetlab-tls -n klosetlab
```

### 인증서 만료일 확인
```bash
kubectl get secret klosetlab-tls -n klosetlab \
  -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -dates
```

### cert-manager가 자동 갱신
Let's Encrypt 인증서 유효기간은 90일. cert-manager가 **만료 30일 전** 자동으로 갱신합니다. 수동으로 할 필요 없음.

### 인증서 강제 재발급 (문제 발생 시)
```bash
kubectl delete secret klosetlab-tls -n klosetlab
# cert-manager가 자동으로 재발급 시작
kubectl get certificate -n klosetlab -w   # -w로 실시간 상태 감시
```

---

## 11. ArgoCD UI 접속

```bash
# ArgoCD 포트 포워딩 (로컬 PC에서 실행)
ssh -i ~/.ssh/klosetlab-key.pem -J ubuntu@3.38.20.22 ubuntu@10.0.11.26 \
  -L 8080:localhost:8080 &
kubectl port-forward svc/argocd-server -n argocd 8080:443

# 브라우저에서 접속
# https://localhost:8080

# 초기 비밀번호 확인
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```

---

## 12. 노드/리소스 모니터링

```bash
# 노드 리소스 사용량
kubectl top nodes

# Pod 리소스 사용량
kubectl top pods -n klosetlab

# 노드 상세 정보 (할당된 리소스)
kubectl describe nodes | grep -A 10 "Allocated resources"
```

---

## 13. ECR 토큰 갱신 CronJob 확인

```bash
# CronJob 목록
kubectl get cronjob -n klosetlab

# 최근 실행 이력 (Job 목록)
kubectl get jobs -n klosetlab | grep ecr

# 가장 최근 Job 로그
kubectl logs -l job-name=ecr-token-refresh-<타임스탬프> -n klosetlab

# 수동으로 즉시 실행
kubectl create job ecr-token-refresh-manual \
  --from=cronjob/ecr-token-refresh \
  -n klosetlab
```

---

## 14. 인그레스 및 라우팅 확인

```bash
# 인그레스 목록 및 주소
kubectl get ingress -n klosetlab

# nginx-ingress Controller 로그 (라우팅 디버깅)
kubectl logs -l app.kubernetes.io/name=ingress-nginx \
  -n ingress-nginx --tail=50
```

---

## 15. 자주 쓰는 명령어 요약

```bash
# === 상태 확인 ===
kubectl get pods -n klosetlab                          # Pod 상태
kubectl get applications -n argocd                     # ArgoCD 상태
kubectl get certificate -n klosetlab                   # TLS 상태

# === 로그 ===
kubectl logs -l app=module-api -n klosetlab --tail=50  # 로그 확인
kubectl logs <pod> -n klosetlab --previous             # 크래시 전 로그

# === 재시작 ===
kubectl rollout restart deployment/module-api -n klosetlab

# === Pod 상세 (이벤트 포함) ===
kubectl describe pod <pod-name> -n klosetlab

# === 롤백 ===
kubectl rollout undo deployment/module-api -n klosetlab

# === 실시간 감시 ===
watch -n 2 kubectl get pods -n klosetlab              # 2초마다 자동 갱신
```

---

## 16. 미완료 항목 (추후 처리)

| 항목 | 담당 | 내용 |
|------|------|------|
| S3 + CloudFront | 다른 팀원 | 프론트엔드 배포 환경 구성 |
| V3_S3_BUCKET 시크릿 | 완료 후 등록 | FE 레포 GitHub Secrets |
| V3_CLOUDFRONT_DISTRIBUTION_ID 시크릿 | 완료 후 등록 | FE 레포 GitHub Secrets |
