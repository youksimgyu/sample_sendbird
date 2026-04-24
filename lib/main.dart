import 'package:flutter/material.dart';
import 'package:sendbird_chat_sdk/sendbird_chat_sdk.dart';

import 'login_page.dart';

// Sendbird 앱 ID (대시보드에서 발급)
const appId = 'YOUR_APP_ID';
// Sendbird Secondary API Token (Platform API 호출용 서버 토큰)
const apiToken = 'YOUR_API_TOKEN';

// 채널 표시 이름 생성 - 내 userId + 상대방 userId 조합
// channel.name 대신 멤버 기반으로 표시해서 1:1 채팅에 적합
String getChannelName(GroupChannel channel) {
  final me = SendbirdChat.currentUser?.userId ?? '';
  final others = channel.members.where((m) => m.userId != me).map((m) => m.userId).toList();

  if (others.isEmpty) return me;
  return '$me, ${others.join(', ')}';
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // SDK 초기화 - 앱 시작 시 한 번만 호출
  // useCollectionCaching: true → 로컬 SQLite DB 자동 관리 (오프라인 지원, 빠른 로딩)
  await SendbirdChat.init(
    appId: appId,
    options: SendbirdChatOptions(
      useCollectionCaching: true,
      useAutoResend: true, // 추가 - 인터넷 복구 시 자동 재전송
    ),
  );
  runApp(const SampleSendbird());
}

class SampleSendbird extends StatelessWidget {
  const SampleSendbird({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: const LoginPage());
  }
}
