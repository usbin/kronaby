# Keepnaby (iOS)

Kronaby의 공식 앱을 대체하는 오픈소스 iOS 컴패니언 앱.
Kronaby Nord 하이브리드 스마트워치를 BLE로 직접 제어하는 프로젝트.

> **Kronaby 공식 앱 지원 중단에 대비하여**, 기존 역공학 깃헙 프로젝트 기반으로 제작됨.
> - 비용 없이 사용할 수 있는 커스텀앱을 지향.
> - GitHub Actions + SideStore로 빌드/설치.
> - 유료 Apple 개발자 계정 없이 개발하여, 7일마다 인증서 갱신이 불가피함. **SideStore 서드파티를 사용하여 간편+반자동화.(참고: https://docs.sidestore.io/docs/intro)**

## 참고 프로젝트

이 프로젝트는 아래 오픈소스 역공학 자료를 참고하여 제작되었음:

- **[victorcrimea/kronaby](https://github.com/victorcrimea/kronaby)** — Kronaby BLE 프로토콜 역공학 문서 및 Node.js 구현
- **[joakar/kronaby](https://github.com/joakar/kronaby)** — Node.js BLE API, npm 패키지

## 빌드 & 설치

### 빌드

GitHub Actions가 push마다 자동 빌드.  
Actions → 최신 run → Artifacts → `Keepnaby-ipa` 다운로드.
- tag 수동으로 달지 않은 이전 릴리즈는 빌드 시점에 일괄 자동 삭제됨

### 설치 - 방법1. Sideloader CLI

```bash
sideloader-cli-x86_64-windows-msvc.exe install Keepnaby.ipa -i
```

- [Sideloader](https://github.com/Dadoum/Sideloader) 다운로드 필요
- `libimobiledevice` dll을 sideloader 폴더에 배치
- iTunes (Apple 공식 사이트 버전) 설치 필요
- 무료 Apple ID — 7일마다 재설치

### 설치 - 방법2. 다운받은 Artifacts의 .ipa를 SideStore 앱으로 설치(권장)

- 기기에 [SideStore](https://docs.sidestore.io/docs/intro) 설치 필요. 자세한 방법은 가이드 문서를 참조.
- SideStore + LocalDevVPN 조합으로 앱 내 Refresh 기능을 사용해 7일마다 반자동 인증서 갱신


---


## 기능

iOS 26.1 + Kronaby Nord 기준으로 제작됨.

### 연결 및 기본 설정
- BLE 스캔 / 연결 / 핸드셰이크 (MsgPack 프로토콜)
- 자동 재연결 + CoreBluetooth State Restoration
- 앱 종료 / BLE 연결 끊김 시 로컬 알림
- 캘리브레이션 (바늘 영점 조정)
- 시각 / 타임존 동기화

### 크라운 Complications
- 날짜 확인, 세계시간, 걸음수, 스톱워치 할당
- `complications([5, mode, 18])` 형식 (실기기 검증)

### 버튼 매핑
- 상단/하단 버튼 × 5가지 이벤트(연속클릭 1~4회+긴 클릭) = **10개 조합**
- 할당 가능 액션:
  - 음악 제어 (재생/일시정지, 이전 곡, 다음 곡)
  - 위치 기록 (GPS + 역지오코딩 + 카카오맵/네이버지도/구글맵/기본지도로 열기)
  - 폰 찾기 (무음모드에서도 소리 재생)
  - IFTTT Webhook / iOS 단축어(앱 열림 강제로 인해 실효성 적음) / URL 요청

### 알림 (ANCS)
- iPhone 알림을 시계에서 진동 + 바늘로 수신
- 3개 슬롯 (위치 1\~3 = 진동 1\~3회)
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
- 세계시간 (2nd Timezone) UTC 오프셋
- 진동 세기 조절 (일반 150ms / 강하게 600ms)
- 설정 전송 시 시계 진동 피드백

## 기술 스택

- **Swift** + **SwiftUI** + **CoreBluetooth**
- **MiniMsgPack** — MsgPack 자체 구현 (외부 의존성 0)
- **XcodeGen** — `project.yml`에서 `.xcodeproj` 자동 생성
- **GitHub Actions** — macOS runner에서 .ipa 빌드 (public repo 무료)
- iOS 16.0+ 타겟


## 미구현 기능

### 구현 예정 있음



### 구현 보류
- **iOS 26.3 Notification Forwarding**
  - Apple의 서드파티 웨어러블 알림 전달 API. 현재 EU 한정 (DMA). 글로벌 확대 시 ANCS 3슬롯 제한 없는 커스텀 알림 가능. 한국이 지원 국가에 포함되기 전까지 구현 불가.
  - (원래 기획했던 것: 휴대폰 앱 알림 발생 -> Keepnaby에서 수신 후 Watch로 커스텀 시그널 전송 -> Watch 시계바늘 정렬과 진동으로 알림)
  - (문제점: 휴대폰 앱 알림은 BLE기기인 Watch만 수신할 수 있어서 Keepnaby가 중간에서 커스텀 시그널로 변환할 방법이 없음)
  - 만약 언젠가 한국이 지원 국가에 포함되면 시계바늘 위치와 진동을 조합해 훨씬 자유로운 확장 가능. 


### 구현 불가
- **HealthKit 연동** — 사이드로딩 앱에서 HealthKit 권한이 부여되지 않음 (App Store 배포 시 해결 가능. 연간 구독료를 부담해야 하기 때문에 사실상 구현 불가)
- **WeatherKit 연동** - 위와 같은 이유로 현재 위치 기온을 가져오는 기능 불가. Call 횟수 제한 있는 api를 활용하는 방안이 있으나 효용성 낮아보여 보류함.

### 발생 조건이 불확실한 문제
- **백그라운드 장기 유지** — CoreBluetooth State Restoration을 구현했으나, 실제 장시간 (수 시간~수일) 백그라운드 유지는 충분히 검증되지 않음. iOS가 ANCS 보안 세션을 내부적으로 만료시키는 것으로 추정되어, 주기적으로 vbat 등의 명령을 전송하면 유지되는 것을 확인. 시계가 물리적으로 앱과 연결이 끊어진 상태가 지속되면 해당 현상 재현되는 한계가 있음.
- **공식 앱 동시 설치 시 간섭** — 공식 앱이 백그라운드에서 BLE 연결을 가로채 설정이 리셋될 수 있음. 공식 앱은 삭제 권장.(공식 앱을 여는 순간 연동 리셋되니 주의)
- **SideStore의 페어링 파일이 깨지는 문제** - SideStore clear cache후 재시도하면 해결됨

## 프로토콜 문서

상세 BLE 프로토콜 명세는 [`docs/kronaby-ble-protocol.md`](docs/kronaby-ble-protocol.md)를 참고.
연결 시퀀스, 명령어 레퍼런스, MsgPack 바이트 해석, commandMap 등.


## 라이선스

MIT License

---
## Change Log
- v1.0.0
  - 기본 기능
- v1.0.1
  - 앱 이름 변경
- v1.0.2
  - Added
    - 확장입력모드: 16종 트리거 할당 추가
    - 위치저장 기능 연결 앱 종류 추가: 네이버지도, 구글맵, 기본지도
  - Fixed
    - 알림 수신 시 진동만 울리고 바늘이 움직이지 않는 문제 수정
- v1.0.3
  - Fixed: 무음 알람 날짜 비트맵 잘못되어 수정
- v1.0.4
  - Added: 6시간 주기 BLE 강제 재연결 — iOS ANCS 보안 세션 만료 대응
- v1.0.5
  - Fixed: 하루가 지나면 ancs 알림을 못 받게 되는 문제 수정
- v1.0.6
  - Modified: Kronaby Nord DnD 지원 안 함으로 판명되어 기능 제거, 재연결 로직 경량화
