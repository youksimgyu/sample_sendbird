# Sendbird Flutter Sample

Sendbird Chat SDK를 활용한 Flutter 샘플 앱입니다.
1:1 채팅 기본 구현 (채널 생성, 메시지 송수신, 읽음 처리)을 포함합니다.

## 시작하기

### 1. Sendbird 대시보드 설정

[Sendbird Dashboard](https://dashboard.sendbird.com/) 에서 앱을 생성하고 아래 값을 발급받으세요.

- **APP ID** — 대시보드 > 앱 선택 > Overview
- **API Token** — 대시보드 > Settings > General > API tokens

### 2. 앱에 적용

`lib/main.dart` 상단에 발급받은 값을 입력하세요.

```dart

const appId = 'YOUR_APP_ID';
const apiToken = 'YOUR_API_TOKEN';
```

### 3. 실행

```bash
flutter pub get
flutter run
```

## 주요 기능

- 로그인 (Session token 기반 인증)
- 1:1 채팅방 생성
- 메시지 송수신 (실시간)
- 읽음 처리 / 안 읽은 메시지 뱃지
- 메시지 수정 / 삭제
- 시스템 메시지 (AdminMessage)
- 오프라인 자동 재전송

## 개발 환경

- Flutter 3.41.6

## 참고

- [Sendbird Flutter SDK 문서](https://sendbird.com/docs/chat/sdk/v4/flutter/overview)
- [Sendbird Platform API 문서](https://sendbird.com/docs/chat/platform-api/v3/overview)