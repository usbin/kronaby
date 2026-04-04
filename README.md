# Kronaby Companion (iOS)

Kronaby의 공식 앱을 대체하는 오픈소스 iOS 컴패니언 앱.
Kronaby Nord 하이브리드 스마트워치를 BLE로 직접 제어하는 프로젝트입니다.

> **Kronaby 공식 앱 지원 중단에 대비하여**, 기존 역공학 깃헙 프로젝트 기반으로 제작됨.
> - 무료 Apple ID + GitHub Actions + SideStore로 빌드/설치.
> - **SideStore 서드파티를 사용하여 7일마다 수동 갱신이 필요.(참고: https://docs.sidestore.io/docs/intro)**

## 참고 프로젝트

이 프로젝트는 아래 오픈소스 역공학 자료를 참고하여 제작되었습니다:

- **[victorcrimea/kronaby](https://github.com/victorcrimea/kronaby)** — Kronaby BLE 프로토콜 역공학 문서 및 Node.js 구현
- **[joakar/kronaby](https://github.com/joakar/kronaby)** — Node.js BLE API, npm 패키지

## 기능

### 연결 및 기본 설정
- BLE 스캔 / 연결 / 핸드셰이크 (MsgPack 프로토콜)
- 자동 재연결 + CoreBluetooth State Restoration
- 연결 시 모든 설정 자동 재전송
- 앱 종료 / BLE 연결 끊김 시 로컬 알림
- 캘리브레이션 (바늘 영점 조정)
- 시각 / 타임존 동기화

### 크라운 Complications
- 날짜 확인, 세계시간, 걸음수, 스톱워치 할당
- `complications([5, mode, 18])` 형식 (실기기 검증)

### 버튼 매핑
- 상단/하단 버튼 × 5가지 이벤트 = **10개 조합**
- 할당 가능 액션:
  - 음악 제어 (재생/일시정지, 이전 곡, 다음 곡)
  - 위치 기록 (GPS + 역지오코딩 + 카카오맵/Apple Maps 연동)
  - 폰 찾기 (무음모드에서도 소리 재생)
  - IFTTT Webhook / iOS 단축어(앱 열림 강제로 인해 실효성 적음) / URL 요청

### 알림 (ANCS)
- iPhone 알림을 시계에서 진동 + 바늘로 수신
- 3개 슬롯 (위치 1~3 = 진동 1~3회)
- 카테고리별 할당 (전화, 소셜, 이메일, 일정 등)
- 시계 펌웨어가 직접 처리 — **앱 종료 후에도 동작**

### 무음 알람
- 최대 8개, 요일별 반복 설정
- 스누즈 (크라운 짧게) / 해제 (크라운 길게)
- `alert_assign`으로 바늘 위치(1~3) 할당

### 기타
- 배터리 잔량 확인 (mV → %)
- 걸음수 확인 (시계 내장 만보기)
- HID 트리거 (카메라 / 미디어 제어 / 음소거)
- 방해금지 (DND) 시간 설정
- 세계시간 (2nd Timezone) UTC 오프셋
- 진동 세기 조절 (일반 150ms / 강하게 600ms)
- 설정 전송 시 시계 진동 피드백

## 기술 스택

- **Swift** + **SwiftUI** + **CoreBluetooth**
- **MiniMsgPack** — MsgPack 자체 구현 (외부 의존성 0)
- **XcodeGen** — `project.yml`에서 `.xcodeproj` 자동 생성
- **GitHub Actions** — macOS runner에서 .ipa 빌드 (public repo 무료)
- iOS 16.0+ 타겟

## 빌드 & 설치

### 빌드

GitHub Actions가 push마다 자동 빌드합니다.  
Actions → 최신 run → Artifacts → `Kronaby-ipa` 다운로드.

### 설치 - 방법1. Sideloader CLI

```bash
sideloader-cli-x86_64-windows-msvc.exe install Kronaby.ipa -i
```

- [Sideloader](https://github.com/Dadoum/Sideloader) 다운로드 필요
- `libimobiledevice` dll을 sideloader 폴더에 배치
- iTunes (Apple 공식 사이트 버전) 설치 필요
- 무료 Apple ID — 7일마다 재설치

### 설치 - 방법2. 다운받은 Artifacts의 .ipa를 SideStore 앱으로 설치

- 기기에 [SideStore](https://docs.sidestore.io/docs/intro) 설치 필요
- SideStore + LocalDevVPN 조합으로 앱 내 Refresh 기능을 사용해 7일마다 인증서 갱신


## 알려진 제한사항

### 미동작
- **앱별 알림 필터 (Bundle ID)** — ANCS `attributeType=0` 필터가 시계 펌웨어에서 무시됨. 카테고리 기반 필터만 동작
- **HealthKit 연동** — 사이드로딩 앱에서 HealthKit 권한이 부여되지 않음 (App Store 배포 시 해결 가능)


### 미검증
- **백그라운드 장기 유지** — CoreBluetooth State Restoration을 구현했으나, 실제 장시간 (수 시간~수일) 백그라운드 유지는 충분히 검증되지 않음
- **공식 앱 동시 설치 시 간섭** — 공식 앱이 백그라운드에서 BLE 연결을 가로채 설정이 리셋될 수 있음. 공식 앱 삭제 권장

### 미구현
- **날씨** — 외부 API 연동 필요
- **iOS 26.3 Notification Forwarding** — Apple의 서드파티 웨어러블 알림 전달 API. 현재 EU 한정 (DMA). 글로벌 확대 시 ANCS 3슬롯 제한 없는 커스텀 알림 가능

## 프로토콜 문서

상세 BLE 프로토콜 명세는 [`docs/kronaby-ble-protocol.md`](docs/kronaby-ble-protocol.md)를 참고하세요.  
연결 시퀀스, 명령어 레퍼런스, MsgPack 바이트 해석, commandMap 등을 포함합니다.

## 라이선스

MIT License
