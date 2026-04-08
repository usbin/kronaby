# ANCS 하루 후 끊김 이슈

## 증상
- 연결 후 ~6-8시간(자고 일어나면) ANCS만 죽음
- 시계 ↔ 폰 BLE 통신은 정상 (명령 주고받기 가능)
- iPhone 알림을 시계가 수신하지 못함
- **블루투스 끄고 켜면 해결됨**
- 공식 Kronaby 앱에서는 이 문제 없었음

## 확인된 사실
- BLE 연결 자체는 끊기지 않음 — ANCS만 선택적으로 죽음
- `cancelPeripheralConnection` → 재연결로는 ANCS 복구 안 됨
- 앱 내 연결 해제 → 앱 재시작 → 자동 연결에서도 ANCS 복구 안 됨
- iOS 블루투스 토글(전체 BLE 스택 리셋)만이 복구 방법
- 공식 앱은 문제 없음 → 펌웨어 결함이 아닌 Keepnaby 측 문제

## 효과 없었던 시도 (모두 코드에서 제거됨)
| 시도 | 결과 |
|------|------|
| 6시간 주기 `cancelPeripheralConnection` 강제 재연결 | ANCS 복구 안 됨 (iOS BLE 스택 리셋이 아니라 단일 peripheral disconnect라서). 제거됨 |
| `BGAppRefreshTask`로 백그라운드에서 강제 재연결 | 위와 같은 이유로 무의미. 제거됨 |
| 10분 keepAlive에서 `complications`/`ancs_filter` 반복 재전송 | 효과 미확인. 공식 앱은 이걸 안 하므로 오히려 원인일 가능성. 제거됨 |
| `onConnected`에서 ANCS 리셋 사이클 (`complications [5,mode,0]` + `alert_assign [0,0,0]` → 2초 후 정상값 재전송) | 재연결 시 ANCS 끄기→켜기로 강제 리프레시 시도. 효과 없음. 제거됨 |

## 추정 원인 (우선순위 순)

### 1. keepAlive ANCS 명령 반복 재전송이 ANCS를 불안정하게 만듦
- Keepnaby: 10분마다 `complications([5, mode, 18])` + `ancs_filter` 재전송
- 공식 앱: 설정을 한 번만 보내고 건드리지 않음
- 반복 재전송이 펌웨어의 ANCS GATT 구독 상태를 매번 흔들어서 결국 만료시키는 것일 수 있음
- **조치 완료: keepAlive 자체 및 ANCS 명령 반복 재전송 모두 제거**

### 2. `didModifyServices` 미구현
- iOS가 GATT 테이블 변경을 알릴 때 Keepnaby가 무시하고 있었음
- 특성 참조가 stale해져서 ANCS 관련 상태가 무효화될 수 있음
- **현재 조치: `didModifyServices` 구현 완료 — 서비스 변경 시 자동 재검색**

### 3. `periodic` (cmd 38) 미사용
- commandMap에 존재하지만 Keepnaby에서 사용하지 않음
- 공식 앱이 이 명령으로 시계에 주기적 heartbeat를 설정할 수 있음
- 확인 방법: 공식 앱 장시간 BLE 캡처

### 4. 공식 앱이 보내는 미확인 명령
- 공식 앱이 연결 유지 중 주기적으로 보내는 명령이 있을 수 있음
- 또는 연결 직후 보내는 명령 중 Keepnaby가 빠뜨린 것이 있을 수 있음
- 확인 방법: 공식 앱 장시간(6-8시간) BLE 캡처 비교

## 아직 시도해볼 것
1. **keepAlive/ANCS 재전송 제거 빌드 하루 테스트** — 가장 유력한 가설. 코드 제거는 완료, 실기기 검증만 남음
2. **공식 앱 장시간 BLE 캡처** — 1번이 안 되면 다음 단계. 공식 앱으로 6-8시간 유지하며 주고받는 패킷 기록
3. **`periodic` 명령 조사** — BLE 캡처에서 공식 앱이 이 명령을 사용하는지 확인
4. **iOS 26.3 Notification Forwarding** — ANCS를 완전히 우회하는 방법. 현재 EU 한정으로 한국 미지원

## 기술 배경
- ANCS는 iOS가 BLE peripheral에 알림을 전달하는 프로토콜
- 시계 펌웨어가 직접 iOS ANCS 서비스에 구독 — 앱은 설정만 전달
- iOS 블루투스 토글은 전체 BLE 스택을 리셋하여 모든 GATT 캐시/세션 초기화
- `cancelPeripheralConnection`은 단일 peripheral만 끊으므로 iOS 내부 ANCS 상태를 리셋하지 못함
