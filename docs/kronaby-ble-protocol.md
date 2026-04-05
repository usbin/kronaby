# Keepnaby — Kronaby BLE 프로토콜 명세 및 iOS 앱 프로젝트 계획

## 프로젝트 개요

Kronaby Nord 하이브리드 스마트워치를 위한 iOS 컴패니언 앱 **Keepnaby** 개발 프로젝트.
Kronaby 사 파산으로 공식 앱 지원 중단 우려 → 오픈소스 역공학 자료 기반으로 자체 앱 구현.

### 요구사항
1. **내 폰 찾기** — 시계에서 크라운 3초 길게 누르면 iPhone에서 소리 재생
2. **알림 수신** — iPhone 알림을 시계에서 진동/바늘 위치로 표시
3. **IFTTT/webhook 액션** — 버튼 조합으로 다양한 자동화 트리거 (공식 앱의 3개 제한 초과)

### 아키텍처

```
iPhone (Swift 앱, CoreBluetooth)
  ├── Kronaby와 BLE 직접 연결 (항상)
  ├── 알림 캡처 → 시계에 진동/바늘 명령
  ├── 버튼 이벤트 수신 → HTTP webhook / Shortcuts 실행
  └── 폰 찾기 → 소리 재생

```

- iPhone이 직접 BLE로 Kronaby 연결 (BLE 범위 ~10m이므로 브릿지 불가)
- 무료 Apple ID + SideStore로 기기 자체에서 7일마다 자동 재서명
- SideStore: https://sidestore.io/
- NAS/PC 서버 불필요 — iPhone 자체적으로 Wi-Fi 페어링 후 백그라운드 재서명

### 참고 자료
- **victorcrimea/kronaby**: https://github.com/victorcrimea/kronaby (프로토콜 역공학 문서)
- **joakar/kronaby**: https://github.com/joakar/kronaby (Node.js BLE API, npm 패키지)
- **Gadgetbridge**: https://codeberg.org/Freeyourgadget/Gadgetbridge (Android 오픈소스, Kronaby 미지원)

---

## BLE 연결 정보

### 광고(Advertisement) UUID (스캔용)
- `0xF431` — Anima/Kronaby 커스텀 식별자
- `0x1812` — HID Service

스캔 시 **두 UUID 모두** 광고하는 기기를 찾아야 함.

### GATT 서비스 & 특성

#### 커스텀 Anima 서비스
| 역할 | UUID |
|------|------|
| **서비스** | `6e406d41-b5a3-f393-e0a9-e6414d494e41` |
| **명령 특성** (read/write) | `6e401980-b5a3-f393-e0a9-e6414d494e41` |
| **알림 특성** (notify) | `6e401981-b5a3-f393-e0a9-e6414d494e41` |

#### 표준 Device Information 서비스 (`0x180A`)
| 특성 | UUID |
|------|------|
| Manufacturer Name | `0x2A29` |
| Model Number | `0x2A24` |
| Serial Number | `0x2A25` |
| Firmware Revision | `0x2A26` |
| Hardware Revision | `0x2A27` |

#### 기타 서비스
| 서비스 | UUID |
|--------|------|
| Generic Access | `0x1800` |
| Generic Attribute | `0x1801` |
| DFU (Nordic) | `00001530-1212-efde-1523-785feabcd123` |

---

## 통신 프로토콜

### MsgPack 인코딩
- 모든 통신은 **MsgPack** 직렬화 (바이너리, 효율적)
- `usemap: true` 코덱 사용 (Map 객체)
- 명령 포맷: `Map { 명령코드(정수) => 데이터 }`

### MsgPack 바이트 해석 규칙
| 바이트 범위 | 의미 | 예시 |
|------------|------|------|
| `00`~`7F` | 양수 정수 (0~127) | `03` = 3 |
| `80`~`8F` | fixmap (하위 4비트 = 항목 수) | `81` = Map 1항목, `82` = Map 2항목 |
| `90`~`9F` | fixarray (하위 4비트 = 요소 수) | `92` = Array 2개, `93` = Array 3개 |
| `A0`~`BF` | fixstr (하위 5비트 = 길이) | `A7` = 7바이트 문자열 |
| `C0` | nil | |
| `C2` / `C3` | false / true | |
| `CC` | uint8 (다음 1바이트) | `CC FF` = 255 |
| `CD` | uint16 (다음 2바이트 BE) | `CD 0100` = 256 |
| `D0` | int8 | `D0 FF` = -1 |
| `D1` | int16 (다음 2바이트 BE) | `D1 0BB8` = 3000 |
| `E0`~`FF` | 음수 정수 (-32~-1) | `FF` = -1 |

**해석 예시:**
```
8103810201 → {3: {2: 1}}
├── 81     = fixmap 1항목
├── 03     = key: 정수 3
├── 81     = value: fixmap 1항목
├── 02     = key: 정수 2
└── 01     = value: 정수 1

810896030000000000 → {8: [3, 0, 0, 0, 0, 0]}
├── 81     = fixmap 1항목
├── 08     = key: 정수 8
├── 96     = value: fixarray 6개
└── 03 00 00 00 00 00 = [3, 0, 0, 0, 0, 0]
```

### 명령어 ID는 동적
- 명령어 이름↔숫자 매핑은 **펌웨어마다 다를 수 있음**
- 연결 후 반드시 `map_cmd` 핸드셰이크로 매핑 테이블을 받아와야 함
- `[0, 0]`, `[0, 1]`, `[0, 2]` 3회 전송 (Array 인코딩) → 응답으로 전체 매핑 수신

---

## 연결 시퀀스

1. `F431` + `1812` UUID로 BLE 스캔
2. 페리퍼럴 연결
3. Anima 서비스(`6e406d41-...`) discover
4. 명령 특성(`6e401980-...`) + 알림 특성(`6e401981-...`) 획득
5. **양쪽 특성 모두 notify subscribe**
6. `map_cmd` 핸드셰이크 (3회):
   - 쓰기: `{0: 0}` → 응답 읽기 (명령어 맵 1/3)
   - 쓰기: `{0: 1}` → 응답 읽기 (명령어 맵 2/3)
   - 쓰기: `{0: 2}` → 응답 읽기 (명령어 맵 3/3)
7. `onboarding_done(1)` 전송 → 바늘 정상 동작
8. `datetime` 전송 → 시간 동기화
9. **준비 완료** — 명령 송수신 가능

---

## 버튼 이벤트 (시계 → 폰)

알림 특성(`6e401981-...`)을 통해 수신.
MsgPack 디코딩 결과: `{button_cmd_name: [버튼번호, 이벤트타입]}`

### 버튼 번호
| 번호 | 물리 위치 |
|------|----------|
| 0 | 상단 푸셔 (Top) |
| 1 | 크라운 (Crown, 중앙) |
| 2 | 하단 푸셔 (Bottom) |

### 이벤트 타입
| 코드 | 이벤트 | 비고 |
|------|--------|------|
| 1 | 1회 클릭 | |
| 2 | 길게 누름 시작 | |
| 3 | 2회 클릭 | |
| 4 | 3회 클릭 | |
| 5 | 4회 클릭 | 공식 앱에 없는 조합 |
| 6 | 1회 클릭 + 길게 누름 | |
| 7 | 2회 클릭 + 길게 누름 | |
| 8 | 3회 클릭 + 길게 누름 | 상단 버튼에서만 확인 |
| 11 | 폰 찾기 (3초 홀드) | **크라운 전용** |
| 12 | 길게 누름 끝 | |

### Raw 바이트 예시 (victorcrimea 문서 기준)
```
상단 1회:    0x8108920001  → {8: [0, 1]}
크라운 2회:  0x8108920103  → {8: [1, 3]}
하단 길게:   0x8108920202  → {8: [2, 2]}
```
※ 여기서 `8`은 `button` 명령의 코드 번호 — 펌웨어마다 다를 수 있으므로 map_cmd로 확인 필요

### 버튼 조합 가능 수
- 버튼 3개 × 이벤트 ~8종 = **이론적으로 24개 이상의 액션 할당 가능**
- 크라운 코드 11(폰찾기)은 예약하면 실질적으로 ~23개

### victorcrimea 문서의 알려진 오류
- 하단 푸셔의 "길게 누름 끝"이 `0x810892010C` (버튼=01)로 기록 → `0x810892020C` (버튼=02)여야 함
- 하단 푸셔의 "1회+길게"가 `0x8108920006` (버튼=00)으로 기록 → `0x8108920206` (버튼=02)여야 함

---

## 명령어 레퍼런스 (폰 → 시계)

### 시간/날짜

#### `datetime` — 시간 동기화
```
파라미터: [년, 월, 일, 시, 분, 초, 요일]
예: [2026, 4, 3, 14, 30, 0, 3]
```

요일 매핑 (주의: 비표준):
| 실제 요일 | 시계 값 |
|----------|---------|
| 화요일 | 0 |
| 수요일 | 1 |
| 목요일 | 2 |
| 금요일 | 3 |
| 토요일 | 4 |
| 일요일 | 5 |
| 월요일 | 6 |

#### `timezone` — 타임존 설정
```
파라미터: [시차, 분차]
예: [9, 0]  → UTC+9 (한국)
```

### 알림/진동

#### `alert` — 알림 전송
```
파라미터: 정수 (알림 타입)
```

#### `alert_assign` — 알림 슬롯 할당 (BLE 캡처 검증 완료)
```
형식: Array [pos1, pos2, pos3]
값: 0 = 비활성, 1 = 활성 (바늘 이동 + 진동)
```
- **활성 슬롯에 반드시 `1`을 설정해야 바늘 이동이 동작함** (BLE 캡처에서 확인)
- `[0,0,0]`이면 진동만 되고 바늘은 안 움직임
- ANCS 슬롯과 알람 슬롯 모두 `1`로 설정 필요 (용도는 ancs_filter/alarm 설정으로 구분)
- **Map 형식 `{위치: 타입}`은 읽기에서 반환되는 형식이지, 쓰기 형식이 아님**

#### `call` — 전화 알림
```
파라미터: [전화번호, 벨울림(0/1)]
isRinging=1이면 진동 시작
```

#### `vibrator_start` — 진동 시작
```
파라미터: 0 (기본 패턴) 또는 [패턴값 배열] (커스텀)
```

#### `vibrator_end` — 진동 중지
```
파라미터: 0
```

#### `vibrator_config` — 진동 패턴 저장 (ANCS 바늘 이동에 필수!)
```
파라미터: [패턴ID, on_ms, off_ms, on_ms, off_ms, ...]
패턴 8 = 1회 진동, 패턴 9 = 2회 진동, 패턴 10 = 3회 진동
```
**이 명령을 보내지 않으면 ANCS 알림 시 바늘이 이동하지 않음!** (BLE 캡처에서 확인)
공식 앱이 보내는 정확한 패턴:
```
vibrator_config([8, 50, 25, 80, 25, 35, 25, 35, 25, 40, 25, 90])    — 1회 진동
vibrator_config([9, 31, 30, 61, 30, 110, 300, 31, 30, 61, 30, 110])  — 2회 진동 (300ms 간격)
vibrator_config([10, 31, 30, 190, 300, 50, 30, 90, 300, 50, 30, 90]) — 3회 진동 (300ms 간격)
```

### 바늘 제어

#### `command_71` — 바늘 미세 조정
```
파라미터: [다이얼번호, 바늘번호, 조정값]
다이얼: 0=메인, 1=오른쪽 서브(Apex), 2=왼쪽 서브(Apex)
바늘: 0=시침, 1=분침
조정값: -6 ~ +6 (양수=시계방향, 음수=반시계방향)
```

#### `stepper_goto` — 스테퍼 모터 직접 제어
```
파라미터: [모터번호, 위치값]
```

#### `stepper_delay` — 스테퍼 모터 딜레이
```
파라미터: 정수
```

#### `stepper_exec_predef` — 사전 정의 패턴 실행
```
파라미터: [handNo1, handNo2, patternIndex2, patternIndex3]
```

#### `recalibrate` — 캘리브레이션 모드
```
파라미터: true (진입) / false (종료)
```

#### `recalibrate_move` — 캘리브레이션 중 바늘 이동
```
파라미터: [모터번호, 스텝수]
```

### 설정

#### `onboarding_done` — 초기 설정 완료
```
파라미터: 1 (완료) / 0 (미완료)
연결 직후 1 전송 필수 — 안 하면 바늘이 계속 회전
```

#### `config_base` — 기본 설정
```
파라미터: [시간해상도(분), 만보기활성화]
```

#### `dnd` — 방해금지
```
파라미터: [활성화(0/1), 시작시, 시작분, 종료시, 종료분]
예: [1, 22, 0, 6, 0]  → 22:00~06:00 방해금지
```

#### `forget_device` — 언페어링
```
파라미터: 0
```

### 기타

#### `alarm` — 무음 알람 설정 (검증 완료)
```
형식: [[시, 분, configByte], ...]
최대 8개, 스누즈=크라운 짧게(10분), 디스미스=크라운 길게
```
**configByte (실기기 검증):**
- `0` = 비활성
- `1` = 1회성 알람 (요일 무관, 다음 시각에 1회 울림) ✅
- `2~254` = 요일 비트마스크 (ISO 표준) ✅
- `255` = 모든 비트 → 즉시 트리거 (주의)

**요일 비트마스크 (ISO 표준, Kronaby datetime 비표준과 다름!):**
| 요일 | bit | 값 |
|------|-----|-----|
| 월 | bit 1 | 2 |
| 화 | bit 2 | 4 |
| 수 | bit 3 | 8 |
| 목 | bit 4 | 16 |
| 금 | bit 5 | 32 |
| 토 | bit 6 | 64 |
| 일 | bit 7 | 128 |

예: 평일 = 2+4+8+16+32 = 62, 주말 = 64+128 = 192, 매일 = 254
**주의: bit 0(값 1)은 "1회성" 의미. 요일 반복 시 bit 0 사용 안 함.**

#### `complications` — 크라운 complication 설정 (검증 완료)
```
형식: complications([5, mode, 18])
첫째(5)와 셋째(18)는 고정, 둘째가 크라운 모드
```
**검증된 모드값:**
| 기능 | mode | 상태 |
|------|------|------|
| 날짜 | 0 | ✅ |
| 세계시간 | 1 | ✅ |
| 걸음수 | 4 | ✅ |
| 스톱워치 | 14 | ✅ |
| 없음 | 15 | 추정 |

**읽기:** `encodeArray([8, batch])` 전송 후 read → `{8: [5, mode, 18]}` 응답
**`set_complication_mode`(cmd 45)는 동작하지 않음** — `complications`(cmd 8)만 유효

#### `steps` / `steps_day` / `steps_target` — 만보기
```
steps_now: 0 전송 → 응답 {57: [걸음수, 일자]} 또는 {57: 걸음수}
steps: [총합, ...요일별값]
steps_day: [걸음수, 날짜]
steps_target: 목표값(정수)
```

**걸음수 바늘 표시 로직 (APK 분석, 실기기 검증):**
```
각도 = (현재걸음수 / 목표걸음수) × 300도    (최대 300도)
분 위치 = 각도 / 360 × 60분

예: 890보 / 1000목표 × 300 = 267도 → 267/360 × 60 = 44.5분 ✅ (실측 44~45분)
```
- **300도 아크** 사용 (360도 아님) → 시계판의 약 50분 범위가 최대
- 시침과 분침 모두 같은 위치로 이동
- 목표 100% 달성 시 300도(50분) 위치, 초과 시 300도에서 멈춤
- `steps_target` + `config_base([1,1])` + `complications([5, 4, 18])` 전부 설정 필요

#### `stillness` — 비활동 알림
```
파라미터: [타임아웃, 윈도우, 시작, 종료]
```

#### `vbat` — 배터리 전압 요청
```
파라미터: 0
```

#### `map_settings` — 설정 맵 쓰기
```
파라미터: 설정 객체 (MsgPack Map)
```

#### `disp_img` / `disp_img_cmd` — E-ink 디스플레이 (일부 모델)
```
disp_img: [픽셀데이터 배열]
disp_img_cmd: 1
```

---

## iOS 앱 개발 계획

### 기술 스택
- **Swift** + **SwiftUI** + **CoreBluetooth** (BLE 통신)
- **NotificationServiceExtension** (알림 캡처, 미구현)
- **MiniMsgPack** (자체 구현, 외부 의존성 0)
- **XcodeGen** (`project.yml` → `.xcodeproj` 자동 생성, CI에서 빌드)
- **GitHub Actions** (macOS runner, public repo 무료)
- **Sideloader CLI** (PC → iPhone 직접 설치, 7일마다 재설치)
- 레포: `git_usbin_kronaby/` (public GitHub repo)

### 구현 완료 기능 (2026-04-05)
| # | 기능 | 명령/방식 | 상태 |
|---|------|----------|------|
| 1 | 프로젝트 세팅 + CI | GitHub Actions → .ipa + Release 자동 생성 | ✅ |
| 2 | 사이드로딩 설치 | SideStore + LocalDevVPN (7일 자동 재서명) | ✅ |
| 3 | BLE 연결 + 핸드셰이크 | map_cmd Array `[0,N]` + read | ✅ |
| 4 | 자동 재연결 + State Restoration | UUID/commandMap 저장 + willRestoreState | ✅ |
| 5 | 연결 시 설정 자동 재전송 | vibrator_config/크라운/걸음수/ANCS/settings | ✅ |
| 6 | 앱 종료/연결 끊김 알림 | 로컬 알림 (applicationWillTerminate + didDisconnect) | ✅ |
| 7 | 캘리브레이션 | recalibrate + recalibrate_move | ✅ |
| 8 | 시각/타임존 설정 | datetime + timezone | ✅ |
| 9 | 크라운 Complications | `complications([5, mode, 18])` | ✅ |
| 10 | 폰 찾기 | 무음모드 재생 + 볼륨 최대화 옵션 + 앱에서 끄기 | ✅ |
| 11 | 버튼 매핑 | 상단 5조합 + 하단 4조합 + 확장입력모드(16종) | ✅ |
| 12 | **ANCS 알림 (바늘+진동)** | vibrator_config + alert_assign `[1,1,0]` + ancs_filter 5원소 | ✅ |
| 13 | 무음 알람 | alarm `[[시,분,config]]` + alert_assign | ✅ |
| 14 | 배터리 | vbat → mV → % | ✅ |
| 15 | 만보기 | steps_now + config_base([1,1]) + steps_target | ✅ |
| 16 | HID 트리거 | triggers `[상단,하단]` (카메라/미디어/음소거) | ✅ |
| 17 | DND 방해금지 | stillness | ✅ |
| 18 | 세계시간 | timezone2 | ✅ |
| 19 | 진동 세기 | vibrator_config (일반 150ms / 강하게 600ms) | ✅ |
| 20 | 위치 기록 | GPS + 역지오코딩 + 지도앱 선택(카카오/네이버/구글/기본) + 진동 피드백 | ✅ |
| 21 | 음악 제어 | MPMusicPlayerController (재생/일시정지/이전/다음) | ✅ |
| 22 | 앱 아이콘 | 도트풍 시계 아이콘 (1024x1024 PNG) | ✅ |
| 23 | 설정 전송 피드백 | 적용 버튼 → 시계 짧은 진동 1회 + UI ✓ 표시 | ✅ |
| 24 | 확장입력모드 (16종) | 하단 길게→진동1→2진4자리 입력→진동2→명령실행 | ✅ |
| 25 | 확장입력모드 바늘 | 진입→11시, 완료→0분부터 목표까지 애니메이션, 취소→즉시복귀 | ✅ |

### 연결 시 자동 재전송
BLE 연결 복원 시 (재연결/앱 재시작) `onConnected` 콜백으로 자동 재전송:
1. `vibrator_config` 패턴 8/9/10 — ANCS 진동+바늘 패턴
2. `complications([5, mode, 18])` — 크라운 + ANCS 바늘 활성화
3. `settings({154:true, 176:1, 178:70, 174:false, 160:1100})` — 펌웨어 기능 활성화
4. `steps_target` + `config_base([1,1])` — 걸음수 목표
5. `alert_assign([활성슬롯])` + `ancs_filter` 3슬롯 + `remote_data` — ANCS 알림 설정
- **공식 앱이 백그라운드에서 연결을 가로채면 설정이 리셋될 수 있음** → 공식 앱 삭제/강제종료 권장

### UI 구조
메인 화면 그룹:
- **자주 사용**: 무음 알람, 위치 기록
- **입출력 매핑**: 크라운, 버튼, 알림 (3열)
- **정보**: 배터리, 걸음수 (탭 → 상단바 업데이트)
- **설정**: 시계 설정, 영점 조정, 시각 설정 (3열)
- 디버그 로그: 기본 숨김, 왼쪽 상단 터미널 아이콘으로 토글
- ⋯ 메뉴: 연결 해제, 기기 삭제, 페어링 도움말

시계 설정 화면: 각 항목별 개별 "적용" 버튼 (전체 일괄 전송 아님)

### 미해결/미구현
| 항목 | 상태 | 비고 |
|------|------|------|
| 앱별 알림 필터 (Bundle ID) | ❌ 미동작 | ANCS attributeType=0 무시됨, 단독 테스트에서도 미동작 |
| 날씨 | 미구현 | 외부 API 연동 필요 |
| HealthKit 연동 | 불가 | 사이드로딩 앱 권한 제한 |
| iOS 26.3 Notification Forwarding | 대기 | EU 한정, 글로벌 확대 시 커스텀 알림 가능 |

### 주의: 요일 매핑 체계
| 용도 | 매핑 | 비고 |
|------|------|------|
| `datetime` (시각 설정) | **Kronaby 비표준** (화=0, 수=1, 목=2, 금=3, 토=4, 일=5, 월=6) | 검증 완료 |
| `alarm` (알람 요일) | **Kronaby 비트마스크** (화=bit1, 수=bit2, 목=bit3, 금=bit4, 토=bit5, 일=bit6, 월=bit7) | 실기기 검증 완료 (2026-04-05) |

alarm 비트마스크는 datetime의 Kronaby 순서를 따릅니다 (bit = kronabyDay + 1).
**주의: 이전에 ISO 표준이라고 기록했으나 잘못된 정보였음! Kronaby 비표준 순서입니다.**

ISO day → alarm 비트 변환:
| ISO | 요일 | Kronaby day | alarm bit | config 값 |
|-----|------|------------|-----------|----------|
| 1 | 월 | 6 | bit 7 | 128 |
| 2 | 화 | 0 | bit 1 | 2 |
| 3 | 수 | 1 | bit 2 | 4 |
| 4 | 목 | 2 | bit 3 | 8 |
| 5 | 금 | 3 | bit 4 | 16 |
| 6 | 토 | 4 | bit 5 | 32 |
| 7 | 일 | 5 | bit 6 | 64 |

### 버튼 매핑 상세
- **상단 버튼**: 1회/2회/3회/4회 클릭 + 길게 = **5개 조합**
- **하단 버튼**: 1회/2회/3회/4회 클릭 = **4개 조합** (길게 = 확장입력모드 고정)
- **크라운**: BLE 이벤트 미전송. complications 전용
- 할당 가능 액션: 폰 찾기, 음악 제어, 위치 기록, IFTTT Webhook, iOS 단축어, URL 요청

### 확장입력모드 (16종)
- **진입**: 하단 길게 누름 → 진동 1회 + 바늘 11시 이동
- **입력**: 하단 1회=0, 2회=1 → 4자리 2진수 입력 (0000~1111 = 0~15)
- **완료**: 4자리 완성 → 진동 2회 + 바늘 0분→목표분 애니메이션(0.3초/스텝) → 3초 유지 → 복귀 → 명령 실행
- **취소**: 입력 중 하단 길게 → 진동 3회 + 바늘 즉시 복귀
- **주의**: 확장입력모드 중에는 상/하단 다른 입력을 인식하지 않음

### 폰 찾기 상세
- AVAudioPlayer `.playback` 카테고리 → 무음모드에서도 스피커 출력
- 시스템 알람 사운드 `/System/Library/Audio/UISounds/alarm.caf` 무한 반복
- 30초 자동 정지 + 앱 UI에서 "소리 끄기" 버튼
- 옵션: "시스템 볼륨 최대화" (MPVolumeView, 작동 후 복원 안 됨 주의)

### 위치 기록 상세
- GPS + CLGeocoder 역지오코딩 → 로컬 알림 + 시계 진동 피드백
- 저장 위치 탭 → 선택한 지도 앱으로 열기
- 지도 앱 선택: 카카오맵 / 네이버지도 / 구글맵 / 기본 지도 (UserDefaults 저장)
- 편집 모드: 개별 선택 삭제 + 전체 삭제

### 알림 매핑 상세 (ANCS)
- **ANCS** = Apple Notification Center Service (iOS 공식 BLE 프로토콜)
- iPhone 알림을 BLE로 연결된 기기에 자동 전달 (앱 개입 없음, 시계 펌웨어가 직접 수신)
- `ancs_filter` 명령으로 시계에 필터 규칙 설정 → 앱 없이도 동작
- **바늘 위치 = 진동 횟수** (하드웨어 제한, 분리 불가)
  - 위치 1 = 진동 1회
  - 위치 2 = 진동 2회
  - 위치 3 = 진동 3회
  - 4~12 미지원
- 각 위치에 여러 ANCS 카테고리를 할당 가능 (비트마스크 OR)
- **앱별 필터(Bundle ID)**: `attributeType=0` + bundleId로 시도했으나 동작하지 않음
- 필터 형식: `[인덱스, 카테고리비트마스크, 속성타입(255=전체), 검색문자열, 진동값(1~3)]`

### iOS 알림 접근 제한
- **iOS에서 서드파티 앱은 다른 앱의 알림을 읽을 수 없음** (보안 정책)
- ANCS만이 BLE 기기에 알림을 전달하는 유일한 경로
- **iOS 26.3 Notification Forwarding** — Apple이 서드파티 웨어러블용 알림 전달 API 추가
  - 앱에서 직접 알림 내용을 수신 → 커스텀 BLE 명령 가능
  - **현재 EU 한정** (DMA 법적 요구사항)
  - 글로벌 확대 시 바늘 위치 자유 제어 가능해짐
- 참고: https://www.macrumors.com/2025/12/15/ios-26-3-notification-forwarding/

### 크라운 Complications 상세
- `set_complication_mode` (cmd 45) — **동작하지 않음** (시계가 에러 반환)
- `complications` (cmd 8) — **올바른 형식: `[5, mode, 18]`**
- 해결 방법: 공식 앱에서 각 모드를 설정 후 배치 읽기(`[8, batch]`)로 현재값 비교 → 두 번째 값만 변화
- `comp_btn`, `comp_def` — Nord 펌웨어 commandMap에 없음
- 첫째(5)와 셋째(18)의 의미: 불명 (다른 모델에서는 다를 수 있음)
- 검증 모드: 날짜(0), 세계시간(1), 걸음수(4), 스톱워치(14), 없음(15 추정)

### 전체 commandMap (74개, Kronaby Nord 펌웨어)
```
 0:map_cmd         1:alarm            2:alert            3:alert_assign
 4:ancs_filter     5:ancs_misuse      6:button           7:call
 8:complications   9:config_base     10:config_debug    11:conn_int_change
12:crash          13:datetime        14:debug_apperror  15:debug_disconnect
16:debug_hardfault 17:debug_reset    18:debug_rssi      19:debug_watchdog
20:dfu_ready      21:diag_event      22:disp_img        23:dump_uart
24:error          25:factory_reset   26:forget_device   27:id_apperror
28:id_error       29:id_forced_hardfault 30:id_hardfault 31:map_buildinfo
32:map_diag       33:map_diag_event  34:map_error       35:map_settings
36:onboarding_done 37:peek_poke     38:periodic         39:postmortem
40:recalibrate    41:recalibrate_move 42:remote_data    43:remove_bond
44:rssi           45:set_complication_mode 46:settings   47:status_buildinfo
48:status_buildinfo_bl 49:status_crash 50:status_diag  51:stepper_def_custom
52:stepper_delay  53:stepper_exec_custom 54:stepper_exec_predef 55:stepper_goto
56:steps_day      57:steps_now       58:steps_target    59:stillness
60:temperature    61:test            62:test_coil       63:test_fcte
64:timezone       65:timezone2       66:triggers        67:upgrade_occurred
68:vbat           69:vbat_sim        70:vibrator_config 71:vibrator_end
72:vibrator_start 73:weekly_sync
```

### 핸드셰이크 프로토콜 상세 (검증 완료)
- **인코딩**: `[0, step]` (MsgPack Array), hex: `920000`, `920001`, `920002`
- **전송**: command 특성(1980)에 `writeValue(.withResponse)` → didWriteValueFor 콜백에서 read
- **수신**: write 완료 500ms 후 `readValue`로 command 특성에서 응답 읽기
- **일반 커맨드**: Map `{cmdId: value}`, `.withResponse`
- **응답 형식**: `{0: {int_id: string_name, ...}}` — id→name 맵, 앱에서 name→id로 반전 저장
- **배치 1**: 40개 커맨드 (map_cmd~postmortem)
- **배치 2**: 34개 커맨드 (recalibrate~weekly_sync)
- **배치 3**: 빈 응답 (추가 커맨드 없음)
- 핸드셰이크 후 `onboarding_done(1)` 전송 필수

### joakar/kronaby 코드의 알려진 버그 (Swift 포팅 시 주의)
1. `writeMotor` — 인자 전달 오류 (callback이 value 자리에 들어감)
2. `writeStepperExecPredef` — 동일한 인자 전달 오류
3. `writeConfigVibrator` — `new []`, `values.add()` (Java 문법, JS에서 동작 안 함)
4. `writeStartVibratorWithPattern` — 동일 `.add()` 버그
5. `writeEinkImg` — 변수 shadowing, 미정의 `data` 참조
6. `startVibrateForIncomingCall` / `stopVibrateForIncomingCall` — 호출만 있고 정의 없음
7. `getDeviceDayOfWeek` — 일요일(JS day 0) 매핑 누락 → default(0=화요일)로 처리됨

**이 코드는 참고용으로만 사용하고, Swift로 새로 구현해야 합니다.**

---

## 사이드로딩 (앱 설치)

### 현재 방식: SideStore + LocalDevVPN
- **SideStore** (https://sidestore.io/) + **LocalDevVPN** 조합
- iPhone 자체에서 7일마다 자동 재서명 (iOS 단축어 자동실행으로 반자동화)
- PC/서버 불필요 — iPhone 단독 동작

### 대안: Sideloader CLI (초기 테스트용)
- **Sideloader** (https://github.com/Dadoum/Sideloader) — 오픈소스, Windows CLI
- 무료 Apple ID로 서명 + USB 설치
- 7일마다 재설치 필요 (무료 계정 제한)

```
sideloader-cli-x86_64-windows-msvc.exe install Keepnaby.ipa -i
```
- `libimobiledevice` dll 필요 (sideloader 폴더에 배치)
- iTunes (Apple 공식 사이트 버전) 설치 필요

### 설치 시 주의사항
- 인증서 충돌 에러 시: 다른 Apple ID 사용 또는 7일 후 기존 인증서 만료 대기
- iPhone 개발자 모드: iOS 26에서는 sideloader로 앱 설치하면 자동 트리거, 설정 → 개인정보 보호 및 보안 → 개발자 모드 활성화
- 시계 페어링 초기화: 상단+하단 푸셔 동시 길게 누르기 → 3회 진동

### 빌드 → 설치 흐름
1. 코드 push → GitHub Actions 자동 빌드
2. Actions → Artifacts → `Keepnaby-ipa` 다운로드
3. `sideloader install Keepnaby.ipa -i` 실행
4. iPhone에서 앱 실행

---

## 진동 패턴 상세 (APK 디컴파일 분석 결과)

### 진동 세기 제어
Kronaby는 **직접적인 진동 세기(amplitude) API가 없음**. 대신 패턴 타이밍(밀리초)으로 간접 제어:
- 값이 클수록 모터 구동 시간이 길어져 더 강하게 느껴짐

### 공식 앱의 2단계 강도
| 강도 | 1회 진동 | 2회 진동 |
|------|----------|----------|
| Normal | `[150]` | `[125, 150, 125]` |
| Stronger | `[600]` | `[400, 150, 400]` |

패턴값 배열 = 밀리초, on/off 교대 (on, off, on, off, ...)

### 기기별 차이 (VibratorPatterns.java)
| 기기 | Normal 예시 | Stronger 예시 |
|------|-------------|---------------|
| FKS927 | `[150]` | `[200]` |
| FKS934 (Pascal) | `[80, 15, 100, 1200]` | `[150, 15, 160, 15, 160, 1200]` |
| BT07 | `[150]` | `[600]` |

### vibrator_config — 커스텀 패턴 저장 (ANCS 바늘 이동에 필수!)
```
파라미터: [pattern_index, on_ms, off_ms, on_ms, off_ms, ...]
인덱스 8 = 1회 진동 패턴, 9 = 2회, 10 = 3회
```
**이 명령을 보내지 않으면 ANCS 알림 시 바늘이 이동하지 않음!** (BLE 캡처에서 확인)

공식 앱이 보내는 패턴 (두 차례의 BLE 캡처에서 동일 확인):
```
vibrator_config([8, 50, 25, 80, 25, 35, 25, 35, 25, 40, 25, 90])    — 1회
vibrator_config([9, 31, 30, 61, 30, 110, 300, 31, 30, 61, 30, 110])  — 2회 (300ms 간격)
vibrator_config([10, 31, 30, 190, 300, 50, 30, 90, 300, 50, 30, 90]) — 3회 (300ms 간격)
```

### vibrator_start — 진동 실행
```
파라미터: 0 (기본) 또는 [ms_values] (커스텀 즉시 실행)
예: vibrator_start([600]) → 600ms 강한 1회 진동
    vibrator_start([150]) → 150ms 약한 1회 진동
    vibrator_start([150, 100, 150]) → 2회 진동 (100ms 간격)
```
