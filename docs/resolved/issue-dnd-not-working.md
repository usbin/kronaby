# DND(방해금지) 동작 안 하는 이슈

## 증상
- 설정 화면에서 DND를 활성화하고 적용해도 해당 시간대에 알림 진동/바늘이 계속 울림
- 로그: `sendCommand 실패: dnd (char=true, map=nil)` — 현재 코드가 보내는 `dnd` 명령이 펌웨어 commandMap에 없어서 전송 자체가 실패
- iPhone의 집중모드/방해금지모드를 켜도 시계는 ANCS 알림을 계속 수신 (OS 레벨 Focus로는 우회 불가 — 실기기 확인됨)

## 근본 원인 (2026-04-15 확정)

**Kronaby Nord 펌웨어에 `dnd` 명령이 존재하지 않음.**

### 안드로이드 APK 역공학 결과
- 공식 앱 코드에는 `Command.DND = "dnd"` 상수와 `writeQuietHours(enabled, startH, startM, endH, endM)` 구현이 있음
- 그러나 `hasDoNotDisturb()` 메서드가 **commandMap에 `"dnd"` 키가 있을 때만** true 반환
- 앱 UI도 `hasDnd == true`일 때만 Quiet Hours 화면 표시
- **모든 Kronaby 모델의 코드가 하나의 APK에 포함**되어 있고, 모델별 지원 여부는 런타임에 commandMap으로 판별

### Kronaby Nord commandMap 전수조사 (74개, 0~73)
- `dnd` 라는 이름의 명령은 **없음** (`docs/kronaby-ble-protocol.md` 549~570 참고)
- 디스플레이가 있는 상위 모델(Kronaby Secured 등)에서만 `dnd`가 commandMap에 포함될 수 있음

### `stillness` (cmd 59) 는 DND가 아님
- 앱 UI 이름: **"Get Moving"** (장시간 비활동 시 움직임 알림)
- 시그니처: `writeStillness(timeout, window, start, end)` — 4개 파라미터
- 용도: "한 시간 이상 안 움직이면 진동으로 알려주는 건강 기능" (애플워치 "일어서기 알림"과 동일)
- 초기 설정 시 공식 앱이 보내는 값: `stillness([0, 0, 0, 0])` = 비활성화
- **DND와 완전히 무관**

## 시도한 것들

| # | 시도 | 결과 | 날짜 |
|---|------|------|------|
| 1 | `stillness`에 `[enabled, startH, startM, endH, endM]` 5-파라미터 전송 | stillness는 4-파라미터 시그니처라 동작 안 함 (추정). 또한 stillness 자체가 DND가 아니라 비활동 알림 기능임 | 2026-04-04 (383b81e) |
| 2 | 명령명을 `stillness` → `dnd`로 변경 | `dnd`가 commandMap에 없어 전송 자체 실패 (`map=nil`) | 2026-04-14 (0eadcc7) |
| 3 | iPhone Focus/방해금지모드 | ANCS 전달이 iOS Focus 상태와 독립적으로 유지됨. 효과 없음 | 2026-04-14 실기기 확인 |
| 4 | APK 역공학으로 DND 전송 방식 확인 | `dnd` 명령은 실제 존재하지만 Nord 모델 commandMap에 없음. 상위 모델 전용 | 2026-04-15 |
| 5 | APK에서 `stillness` 용도 확인 | "Get Moving" = 비활동 알림, DND 아님 확정 | 2026-04-15 |

## 현재 진행 중

### `settings` (cmd 46) 미사용 키 탐색
- `map_settings` (cmd 35) 읽기 기능을 Keepnaby에 구현함 (2026-04-15)
- 시계에서 `map_settings` 페이지를 읽어 settings 키 이름 전체 목록을 확인 예정
- DND 관련 settings 키가 있는지 확인하는 것이 목적

**구현 위치:**
- `Sources/BLE/BLEManager.swift` — `readSettingsMap()`, `settingsMap` 프로퍼티
- `Sources/UI/WatchSettingsView.swift` — "펌웨어 Settings 키 탐색" 섹션

**기대 확률: 낮음** — APK에서 DND는 `settings` 키가 아니라 `"dnd"` 독립 명령으로 구현되어 있음. Remote Config 기본값에도 DND 관련 settings 키 없음.

## 남은 가능한 방향

1. **`map_settings` 결과 확인 후 판단** — settings 키에 DND 관련 항목이 있으면 포팅
2. **앱 측 스케줄러로 에뮬레이션** — DND 시간대 진입 시 `ancs_filter` 슬롯을 전부 삭제하고 종료 시 복원. `BGAppRefreshTask` 타이밍 불확정으로 정확도 문제 있음. **보류**
3. **DND 기능 제거** — 펌웨어가 지원하지 않으므로 UI 삭제. **보류**

## 현재 코드 위치
- `Sources/UI/WatchSettingsView.swift:96` — 적용 버튼에서 `sendCommand(name: "dnd", ...)` 호출
- `Sources/KeepnabyApp.swift:59` — 연결 시 재전송 경로에서 동일 호출

## 기술 배경
- ANCS는 iOS가 BLE peripheral에 알림을 직접 전달하는 프로토콜. 앱 개입 없음
- 시계 펌웨어가 ANCS에 직접 구독하므로, 앱에서 DND를 구현하려면:
  - 펌웨어 자체 DND 기능을 쓰거나 (전용 명령 or settings 키)
  - `ancs_filter`를 시간대별로 토글하거나
  - iOS 측에서 ANCS 전달을 막아야 함 (현재 iOS API로는 불가 — Focus 모드로도 안 됨)

## 결론

해당 모델은 DND를 펌웨어 차원에서 지원하지 않는 것으로 판명되어 이슈 종료함.
