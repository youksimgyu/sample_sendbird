import 'package:flutter/material.dart';
import 'package:sample_sendbird/main.dart';
import 'package:sendbird_chat_sdk/sendbird_chat_sdk.dart';

import 'chat_page.dart';

class ChannelListPage extends StatefulWidget {
  const ChannelListPage({super.key});

  @override
  State<ChannelListPage> createState() => _ChannelListPageState();
}

class _ChannelListPageState extends State<ChannelListPage> {
  late GroupChannelCollection _collection;

  @override
  void initState() {
    super.initState();
    _initCollection();
  }

  void _initCollection() {
    // GroupChannelListQuery: 채널 목록 조회 쿼리
    // latestLastMessage: 마지막 메시지 최신순 정렬
    // limit: 한 번에 불러올 채널 수
    final query = GroupChannelListQuery()
      ..order = GroupChannelListQueryOrder.latestLastMessage
      ..limit = 20;

    // GroupChannelCollection: 채널 목록 실시간 관리
    // 로컬 캐시 + 서버 동기화 자동 처리
    // handler: 채널 추가/수정/삭제 이벤트 수신
    _collection = GroupChannelCollection(
      query: query,
      handler: _ChannelCollectionHandler(onUpdate: () => setState(() {})),
    );

    // 첫 페이지 로드 - onChannelsAdded 콜백으로 _channels에 추가됨
    _collection.loadMore();
  }

  Future<void> _showCreateChannelDialog() async {
    final controller = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('새 채팅방'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '상대방 User ID'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _createChannel(controller.text.trim());
            },
            child: const Text('만들기'),
          ),
        ],
      ),
    );
  }

  Future<void> _createChannel(String otherUserId) async {
    if (otherUserId.isEmpty) return;

    try {
      // GroupChannelCreateParams: 채널 생성 파라미터
      // isDistinct: true → 같은 멤버 조합이면 기존 채널 재사용 (1:1 채팅 필수)
      // customType: 채널 분류용 커스텀 타입 (목록 필터링 기준)
      final params = GroupChannelCreateParams()
        ..userIds = [SendbirdChat.currentUser!.userId, otherUserId]
        ..isDistinct = true
        ..customType = '1on1'
        ..name = otherUserId;

      final channel = await GroupChannel.createChannel(params);
      debugPrint('[Channel] 채널 생성 성공: ${channel.channelUrl}');

      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(channel: channel)));
      }
    } catch (e) {
      debugPrint('[Channel] 채널 생성 실패: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('채팅방 생성 실패: $e')));
      }
    }
  }

  // 채널 꾹 누르면 이름 수정 다이얼로그 표시
  // channel.name 수정 (getChannelName과 별개로 Sendbird 서버에 저장되는 값)
  Future<void> _showEditChannelDialog(GroupChannel channel) async {
    final controller = TextEditingController(text: channel.name);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('채널 이름 수정'),
        content: TextField(controller: controller),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await channel.updateChannel(GroupChannelUpdateParams()..name = controller.text.trim());
              debugPrint('[Channel] 채널 이름 수정 성공');
            },
            child: const Text('수정'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Collection dispose 필수 - 안 하면 메모리 누수 발생
    _collection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Channels')),
      floatingActionButton: FloatingActionButton(onPressed: _showCreateChannelDialog, child: const Icon(Icons.add)),
      body: ListView.builder(
        itemCount: _collection.channelList.length,
        itemBuilder: (_, index) {
          final channel = _collection.channelList[index];
          return ListTile(
            // getChannelName: 멤버 userId 조합으로 표시 (내꺼, 상대꺼)
            title: Text(getChannelName(channel)),
            // lastMessage: 채널 객체에 포함된 마지막 메시지
            subtitle: Text(channel.lastMessage?.message ?? ''),
            // unreadMessageCount: 내 기준 안 읽은 메시지 수
            trailing: channel.unreadMessageCount > 0
                ? CircleAvatar(
                    radius: 10,
                    child: Text('${channel.unreadMessageCount}', style: const TextStyle(fontSize: 10)),
                  )
                : null,
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatPage(channel: channel))),
            onLongPress: () => _showEditChannelDialog(channel),
          );
        },
      ),
    );
  }
}

// GroupChannelCollectionHandler: 채널 목록 실시간 이벤트 수신
class _ChannelCollectionHandler extends GroupChannelCollectionHandler {
  final VoidCallback onUpdate;

  _ChannelCollectionHandler({required this.onUpdate});

  @override
  void onChannelsAdded(GroupChannelContext context, List<GroupChannel> added) {
    // 새 채널 추가 (loadMore 결과 + 실시간 채널 생성)
    onUpdate();
  }

  @override
  void onChannelsUpdated(GroupChannelContext context, List<GroupChannel> updated) {
    onUpdate();
  }

  @override
  void onChannelsDeleted(GroupChannelContext context, List<String> deletedUrls) {
    onUpdate();
  }
}
