import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:sample_sendbird/main.dart';
import 'package:sendbird_chat_sdk/sendbird_chat_sdk.dart';

class ChatPage extends StatefulWidget {
  final GroupChannel channel;
  const ChatPage({super.key, required this.channel});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late MessageCollection _collection;
  final _scrollController = ScrollController();
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initCollection();
    _scrollController.addListener(_onScroll);
  }

  void _initCollection() {
    // MessageCollection: 메시지 목록 실시간 관리
    // 로컬 캐시 + 서버 동기화 + 실시간 수신 자동 처리
    // params: 기본값 사용 (previousResultSize: 20, nextResultSize: 0)
    _collection = MessageCollection(
      channel: widget.channel,
      params: MessageListParams()
        ..previousResultSize = 15
        ..reverse = true,
      handler: _MessageCollectionHandler(onUpdate: () => setState(() {})),
    );

    // 메시지 로드 시작 - onMessagesAdded 콜백으로 _messages에 추가됨
    _collection.initialize();

    // 채팅방 진입 시 읽음 처리 → unreadMessageCount 초기화
    widget.channel.markAsRead();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (_collection.hasPrevious && !_collection.isLoading) {
        _loadPreviousMessages();
      }
    }
  }

  Future<void> _loadPreviousMessages() async {
    try {
      await _collection.loadPrevious();
    } catch (e) {
      debugPrint('[Message] loadPrevious 실패: $e');
    }
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    // 메시지 전송
    // 전송 즉시 pending 메시지가 onMessagesAdded로 옴 → UI에 바로 표시
    // 서버 응답 후 succeeded로 변경 → onMessagesUpdated로 교체
    widget.channel.sendUserMessage(
      UserMessageCreateParams(message: text),
      handler: (message, error) {
        if (error != null) {
          debugPrint('[Message] 전송 실패: ${error.message}');
          return;
        }
      },
    );
  }

  // 내 메시지 꾹 누르면 수정/삭제 옵션 표시
  // 상대방 메시지 또는 삭제된 메시지는 옵션 없음
  Future<void> _showMessageOptions(BaseMessage msg) async {
    final isMe = msg.sender?.userId == SendbirdChat.currentUser?.userId;
    if (!isMe) return;
    if (msg.customType == 'deleted') return;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('수정'),
              onTap: () {
                Navigator.pop(context);
                _showEditDialog(msg as UserMessage);
              },
            ),
            ListTile(
              title: const Text('삭제'),
              onTap: () async {
                Navigator.pop(context);
                // 실제 삭제 대신 내용을 변경해서 흔적 남기기
                // customType: 'deleted' 로 UI에서 구분
                await widget.channel.updateUserMessage(
                  msg.messageId,
                  UserMessageUpdateParams()
                    ..message = '삭제된 메시지입니다'
                    ..customType = 'deleted',
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // 메시지 수정 다이얼로그
  // 수정 완료 시 onMessagesUpdated 콜백으로 자동 반영
  Future<void> _showEditDialog(UserMessage msg) async {
    final controller = TextEditingController(text: msg.message);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('메시지 수정'),
        content: TextField(controller: controller),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('취소')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await widget.channel.updateUserMessage(
                msg.messageId,
                UserMessageUpdateParams()..message = controller.text.trim(),
              );
            },
            child: const Text('수정'),
          ),
        ],
      ),
    );
  }

  // AdminMessage 전송 (Platform API 사용)
  // SDK에서는 수신만 가능, 발송은 서버에서만 가능
  // 테스트 목적으로 앱에서 직접 호출 (프로덕션에서는 내 서버에서 호출)
  Future<void> _sendAdminMessage(String message) async {
    await http.post(
      Uri.parse('https://api-$appId.sendbird.com/v3/group_channels/${widget.channel.channelUrl}/messages'),
      headers: {'Api-Token': apiToken, 'Content-Type': 'application/json'},
      body: jsonEncode({'message_type': 'ADMM', 'message': message}),
    );
    debugPrint('[AdminMessage] 전송: $message');
  }

  bool _shouldShowDate(int index) {
    final list = _collection.messageList;

    // 가장 오래된 메시지 (맨 끝) 는 항상 날짜 표시
    if (index == list.length - 1) return true;

    final current = list[index];
    final next = list[index + 1]; // 내림차순이라 index+1이 더 오래됨

    final currentDate = DateTime.fromMillisecondsSinceEpoch(current.createdAt);
    final nextDate = DateTime.fromMillisecondsSinceEpoch(next.createdAt);

    return currentDate.day != nextDate.day || currentDate.month != nextDate.month || currentDate.year != nextDate.year;
  }

  @override
  void dispose() {
    // Collection dispose 필수 - 안 하면 메모리 누수 발생
    _scrollController.dispose();
    _collection.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(getChannelName(widget.channel)),
        actions: [
          // 테스트용 AdminMessage 전송 버튼
          IconButton(icon: const Icon(Icons.info_outline), onPressed: () => _sendAdminMessage('시스템 메시지 테스트')),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Scrollbar(
                controller: _scrollController,
                child: ListView.builder(
                  controller: _scrollController,
                  reverse: true, // 최신 메시지가 아래로 오도록
                  itemCount: _collection.messageList.length,
                  itemBuilder: (_, index) {
                    final msg = _collection.messageList[index];
                    final showDate = _shouldShowDate(index);
                    final isMe = msg.sender?.userId == SendbirdChat.currentUser?.userId;
                    final isDeleted = msg.customType == 'deleted';

                    // AdminMessage: 가운데 시스템 메시지로 표시
                    if (msg is AdminMessage) {
                      return Column(
                        children: [
                          if (showDate) _buildDateDivider(msg.createdAt),
                          Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.grey[200],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(msg.message, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ),
                          ),
                        ],
                      );
                    }

                    // UserMessage / FileMessage
                    return Column(
                      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        if (showDate) _buildDateDivider(msg.createdAt),
                        GestureDetector(
                          onLongPress: () => _showMessageOptions(msg),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isMe ? Colors.purple : Colors.grey[300],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              isDeleted ? '삭제된 메시지입니다' : (msg is UserMessage ? msg.message : '[file]'),
                              style: TextStyle(
                                color: isDeleted ? Colors.grey : (isMe ? Colors.white : Colors.black),
                                fontStyle: isDeleted ? FontStyle.italic : FontStyle.normal,
                              ),
                            ),
                          ),
                        ),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _buildSendingStatus(msg)),
                      ],
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      decoration: const InputDecoration(hintText: 'Message...'),
                    ),
                  ),
                  IconButton(onPressed: _sendMessage, icon: const Icon(Icons.send)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 전송 상태에 따라 다른 위젯 표시
  // pending: 로딩 → succeeded: 시간 → failed: 에러 아이콘
  Widget _buildSendingStatus(BaseMessage msg) {
    switch (msg.sendingStatus) {
      case SendingStatus.pending:
        return const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1));
      case SendingStatus.failed:
        return const Icon(Icons.error_outline, size: 12, color: Colors.red);
      case SendingStatus.succeeded:
        return Text(_formatTime(msg.createdAt), style: const TextStyle(fontSize: 10, color: Colors.grey));
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildDateDivider(int timestamp) {
    final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ),
    );
  }
}

// MessageCollectionHandler: 메시지 목록 실시간 이벤트 수신
class _MessageCollectionHandler extends MessageCollectionHandler {
  final VoidCallback onUpdate;

  _MessageCollectionHandler({required this.onUpdate});

  @override
  void onMessagesAdded(MessageContext context, GroupChannel channel, List<BaseMessage> added) {
    onUpdate();
  }

  @override
  void onMessagesUpdated(MessageContext context, GroupChannel channel, List<BaseMessage> updated) {
    onUpdate();
  }

  @override
  void onMessagesDeleted(MessageContext context, GroupChannel channel, List<BaseMessage> deleted) {
    onUpdate();
  }

  @override
  void onChannelUpdated(GroupChannelContext context, GroupChannel channel) {
    // 채널 정보 변경 (이름, 멤버 등)
  }

  @override
  void onChannelDeleted(GroupChannelContext context, String deletedChannelUrl) {
    // 채널 삭제됨 → 채팅방 화면 닫기 처리 필요
  }

  @override
  void onHugeGapDetected() {
    // 오프라인 후 재연결 시 메시지 차이가 너무 클 때 호출
    // 전체 메시지 초기화 후 다시 로드
    onUpdate();
  }
}

// Unix timestamp(ms) → HH:mm 형식으로 변환
String _formatTime(int timestamp) {
  final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
