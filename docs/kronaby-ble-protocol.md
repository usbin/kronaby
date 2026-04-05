# Kronaby BLE Protocol Reference

Kronaby 하이브리드 스마트워치의 BLE 통신 프로토콜 명세.  
Kronaby Nord 모델 기준, 실기기 검증 완료 (2026-04-04).

> 참고 프로젝트:
> - [victorcrimea/kronaby](https://github.com/victorcrimea/kronaby) — 프로토콜 역공학
> - [joakar/kronaby](https://github.com/joakar/kronaby) — Node.js BLE API

---

## BLE 연결 정보

### 광고(Advertisement) UUID
- `0xF431` — Anima/Kronaby 커스텀 식별자
- `0x1812` — HID Service

페어링 모드에서만 광고합니다. 페어링 모드 진입: 상단+하단 푸셔 동시 길게 누르기 → 3회 진동 후 바늘 회전.

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

## MsgPack 프로토콜

모든 통신은 **MsgPack** 바이너리 직렬화.

### 바이트 해석 규칙
| 바이트 범위 | 의미 | 예시 |
|------------|------|------|
| `00`~`7F` | 양수 정수 (0~127) | `03` = 3 |
| `80`~`8F` | fixmap (하위 4비트 = 항목 수) | `81` = Map 1항목 |
| `90`~`9F` | fixarray (하위 4비트 = 요소 수) | `93` = Array 3개 |
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
├── 81 = fixmap 1항목
├── 03 = key: 3
├── 81 = value: fixmap 1항목
├── 02 = key: 2
└── 01 = value: 1

810893050012 → {8: [5, 0, 18]}
├── 81 = fixmap 1항목
├── 08 = key: 8
├── 93 = fixarray 3개
└── 05 00 12 = [5, 0, 18]
```

### 명령 포맷
- **일반 커맨드**: `{cmdId: value}` (MsgPack Map)
- **핸드셰이크**: `[0, batch]` (MsgPack Array)
- **명령어 ID는 동적** — 펌웨어마다 다를 수 있으므로 `map_cmd` 핸드셰이크 필수

---

## 연결 시퀀스

```
1. BLE 스캔 (F431 서비스 필터) → 페어링 모드 시계만
2. 연결 → 서비스 discover → 명령/알림 특성 notify subscribe
3. map_cmd 핸드셰이크:
   - [0, 0] write(.withResponse) → 500ms 후 readValue → 배치 1 (40개 커맨드)
   - [0, 1] write → read → 배치 2 (34개 커맨드)
   - [0, 2] write → read → 빈 응답
4. 응답 형식: {0: {int_id: "command_name", ...}} → name→id로 반전 저장
5. onboarding_done(1) 전송 → 바늘 정상 동작
6. config_base([1, 1]) → 만보기 활성화
7. complications([5, mode, 18]) → 크라운 설정
8. datetime 전송 → 시각 동기화
```

---

## 버튼 이벤트 (시계 → 폰)

알림 특성(`6e401981-...`)을 통해 수신.  
형식: `{button_cmd_id: [버튼번호, 이벤트타입]}`

### 버튼 번호
| 번호 | 물리 위치 |
|------|----------|
| 0 | 상단 푸셔 (Top) |
| 1 | 크라운 (Crown) — **BLE 이벤트 미전송**, 펌웨어 내부 처리 |
| 2 | 하단 푸셔 (Bottom) |

### 이벤트 타입
| 코드 | 이벤트 |
|------|--------|
| 1 | 1회 클릭 |
| 2 | 길게 누름 시작 |
| 3 | 2회 클릭 |
| 4 | 3회 클릭 |
| 5 | 4회 클릭 |
| 11 | 폰 찾기 (크라운 3초 홀드) |
| 12 | 길게 누름 끝 |

※ 크라운은 일반 버튼 이벤트를 보내지 않음. Complications 표시만 가능.

---

## 명령어 레퍼런스 (폰 → 시계)

### 시각/타임존

#### `datetime`
```
파라미터: [년, 월, 일, 시, 분, 초, 요일]
```

**요일 매핑 (Kronaby 비표준):**
| 실제 요일 | 값 |
|----------|-----|
| 화 | 0 |
| 수 | 1 |
| 목 | 2 |
| 금 | 3 |
| 토 | 4 |
| 일 | 5 |
| 월 | 6 |

#### `timezone`
```
파라미터: [시차, 분차]
예: [9, 0] → UTC+9
```

#### `timezone2` — 세계시간 (2nd timezone)
```
파라미터: [시차, 분차]
```

### 크라운 Complications

#### `complications` — 크라운 설정 ✅
```
형식: complications([5, mode, 18])
첫째(5)와 셋째(18)는 고정, 둘째가 크라운 모드
```

| 기능 | mode |
|------|------|
| 날짜 | 0 |
| 세계시간 | 1 |
| 걸음수 | 4 |
| 스톱워치 | 14 |
| 없음 | 15 |

읽기: `[8, batch]` Array 전송 후 read → `{8: [5, mode, 18]}` 응답

**`set_complication_mode`(cmd 45)는 동작하지 않음** — `complications`만 유효

### 알림/진동

#### `alert_assign` — 알림 슬롯 할당 ✅
```
쓰기 형식: Array [pos1_type, pos2_type, pos3_type]  (길이 3 또는 6)
읽기 형식: Map {위치: 타입} (배치 읽기 시 반환)
타입: 0 = ANCS 알림, 1 = 무음 알람
예: [0, 1, 0] → pos1=알림, pos2=알람, pos3=알림
```
**주의: 쓰기는 반드시 Array 형식. Map 형식으로 보내면 진동만 동작하고 바늘 이동 안 됨.**

#### `ancs_filter` — ANCS 알림 필터
```
활성: [인덱스, 카테고리비트마스크, 속성타입, 검색문자열, 진동값]
삭제: [인덱스]

속성타입: 255 = 전체 (카테고리 기반)
진동값: 1~3 (= 바늘 위치)
```

ANCS 카테고리 비트마스크: `1 << (rawValue + 8)`
| 카테고리 | rawValue | 비트마스크 |
|----------|----------|-----------|
| Other | 0 | 256 |
| IncomingCall | 1 | 512 |
| MissedCall | 2 | 1024 |
| Social | 4 | 4096 |
| Schedule | 5 | 8192 |
| Email | 6 | 16384 |
| News | 7 | 32768 |

**앱별 필터(attributeType=0 + bundleId)는 Nord 펌웨어에서 미동작**

#### `vibrator_start` / `vibrator_end` / `vibrator_config`
```
vibrator_start: 0 (기본) 또는 [ms값 배열] (커스텀)
vibrator_end: 0
vibrator_config: [인덱스(8+), ...ms패턴값]
```

패턴값 배열 = 밀리초, on/off 교대. 값이 클수록 강하게.  
Normal: `[150]`, Stronger: `[600]`

### 무음 알람

#### `alarm` ✅
```
형식: [[시, 분, configByte], ...]
최대 8개
```

**configByte:**
| 값 | 의미 |
|----|------|
| 0 | 비활성 |
| 1 | 1회성 (다음 시각에 울림) |
| 2~254 | 요일 비트마스크 (ISO 표준) |
| 255 | 즉시 트리거 |

**요일 비트마스크 (ISO 표준 — datetime의 Kronaby 비표준과 다름!):**
| 요일 | bit | 값 |
|------|-----|-----|
| 월 | 1 | 2 |
| 화 | 2 | 4 |
| 수 | 3 | 8 |
| 목 | 4 | 16 |
| 금 | 5 | 32 |
| 토 | 6 | 64 |
| 일 | 7 | 128 |

스누즈: 크라운 짧게 (10분), 해제: 크라운 길게  
**`alert_assign`으로 위치(1~3) 할당 필수** — 없으면 진동 안 함

### 캘리브레이션

#### `recalibrate`
```
true → 캘리브레이션 모드 진입
false → 종료
```

#### `recalibrate_move`
```
파라미터: [모터번호, 스텝수]
모터 0 = 시침, 모터 1 = 분침
양수 = 시계방향, 음수 = 반시계방향
```

`recalibrate(true)` 전송 후에만 동작

### 만보기

#### `steps_now`
```
파라미터: 0
응답: {cmd_id: [걸음수, 일자]} 또는 {cmd_id: 걸음수}
```

#### `steps_target`
```
파라미터: 목표값 (정수)
```

**걸음수 바늘 표시 (APK 분석 + 실기기 검증):**
```
각도 = (현재걸음수 / 목표걸음수) × 300도    (최대 300도)
분 위치 = 각도 / 360 × 60분
```
- 300도 아크 사용 (360도 아님) → 시계판 ~50분 범위가 최대
- 시침과 분침 모두 같은 위치로 이동
- `steps_target` + `config_base([1,1])` + `complications([5, 4, 18])` 전부 필요

### 설정

#### `onboarding_done`
```
1 = 완료 (연결 직후 필수), 0 = 미완료
```

#### `config_base`
```
[시간해상도(분), 만보기활성화(0/1)]
```

#### `triggers` — HID 트리거
```
[상단버튼값, 하단버튼값]
0 = 없음, 1 = 카메라, 2 = 미디어, 3 = 음소거
```

#### `vbat` — 배터리
```
파라미터: 0
응답: {cmd_id: 밀리볼트}
퍼센트 변환: (mV - 2000) / 1000 × 100 (CR2025 기준)
```

---

## commandMap (74개, Kronaby Nord)

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

※ 명령어 ID는 펌웨어마다 다를 수 있음. 반드시 `map_cmd` 핸드셰이크로 확인.

---

## 주의사항

### 요일 매핑 체계 차이
| 용도 | 매핑 |
|------|------|
| `datetime` (시각 설정) | **Kronaby 비표준** (화=0, 수=1, ..., 월=6) |
| `alarm` (알람 요일) | **ISO 표준** (월=1 → bit 1, ..., 일=7 → bit 7) |

같은 시계인데 두 명령이 다른 요일 체계를 사용합니다.

### victorcrimea/kronaby 문서의 알려진 오류
- 하단 푸셔 "길게 누름 끝": `0x810892010C` (버튼=01) → `0x810892020C` (버튼=02)
- 하단 푸셔 "1회+길게": `0x8108920006` (버튼=00) → `0x8108920206` (버튼=02)
