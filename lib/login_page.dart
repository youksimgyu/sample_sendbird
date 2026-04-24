import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sample_sendbird/main.dart';
import 'package:sendbird_chat_sdk/sendbird_chat_sdk.dart';

import 'channel_list_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _userIdController = TextEditingController();

  // Sendbird Platform API로 session token 발급
  // session token: 앱에서 Sendbird에 connect할 때 사용하는 유저 인증 토큰
  // expires_at: 만료 시간 (Unix timestamp ms), 7일 후 만료로 설정
  Future<String?> _getSessionToken(String userId) async {
    final response = await http.post(
      Uri.parse('https://api-$appId.sendbird.com/v3/users/$userId/token'),
      headers: {'Api-Token': apiToken, 'Content-Type': 'application/json'},
      body: jsonEncode({'expires_at': DateTime.now().add(const Duration(days: 7)).millisecondsSinceEpoch}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['token'];
    }

    // 유저가 없으면 400 에러 → null 반환
    // connect() 호출 시 userId가 없으면 Sendbird가 자동 생성해줌
    debugPrint('[SessionToken] 발급 실패: ${response.statusCode} ${response.body}');
    return null;
  }

  Future<void> _login() async {
    final userId = _userIdController.text.trim();
    if (userId.isEmpty) return;

    // session token 발급
    // token이 null이면 accessToken 없이 connect → Sendbird가 유저 자동 생성
    final token = await _getSessionToken(userId);

    // Sendbird 서버에 WebSocket 연결
    // token이 없으면 테스트 모드 (보안 취약 → 프로덕션에서는 반드시 token 필요)
    await SendbirdChat.connect(userId, accessToken: token);

    // SessionHandler 등록 - token 만료 시 자동 갱신 처리
    // connect() 이후에 등록해야 함
    SendbirdChat.setSessionHandler(MySessionHandler(fetchToken: _getSessionToken));

    debugPrint('[Login] 로그인 성공: $userId');

    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const ChannelListPage()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(
              controller: _userIdController,
              decoration: const InputDecoration(labelText: 'User ID'),
            ),
            const SizedBox(height: 24),
            ElevatedButton(onPressed: _login, child: const Text('Sign In')),
          ],
        ),
      ),
    );
  }
}

// SessionHandler: session token 만료 시 SDK가 자동으로 호출
// onAccessTokenRequired → 새 token 발급 → SDK가 자동 재연결
// onSessionClosed → 갱신 실패 → 로그인 화면으로 이동 처리 필요
class MySessionHandler extends SessionHandler {
  final Future<String?> Function(String userId) fetchToken;

  MySessionHandler({required this.fetchToken});

  @override
  void onAccessTokenRequired(AccessTokenRequester accessTokenRequester) async {
    final userId = SendbirdChat.currentUser?.userId;
    if (userId == null) {
      // 유저 정보 없으면 갱신 실패 처리
      await accessTokenRequester.onFail();
      return;
    }

    final token = await fetchToken(userId);
    // 새 token을 SDK에 전달 → SDK가 자동으로 재연결
    // token이 null이면 onSessionClosed 호출됨
    await accessTokenRequester.onSuccess(token);
  }

  @override
  void onSessionClosed() {
    // token 갱신 실패 또는 token이 null로 전달된 경우 호출
    // 로그인 화면으로 이동 처리 필요 (Navigator, GetX 등 활용)
    debugPrint('[SessionHandler] 세션 종료 → 로그인 화면으로 이동 필요');
  }

  @override
  void onSessionRefreshed() {
    // token 갱신 성공 시 호출 (선택적 구현)
    debugPrint('[SessionHandler] 토큰 갱신 성공');
  }

  @override
  void onSessionError(SendbirdException e) {
    // SDK 내부 에러로 갱신 실패 시 호출 (선택적 구현)
    debugPrint('[SessionHandler] 토큰 갱신 에러: ${e.message}');
  }
}
