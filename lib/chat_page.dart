import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late final MessageCollection _collection;
  final _scrollController = ScrollController();
  final _controller = TextEditingController();
  // TextField onChanged에서 @ 감지
  bool _showMentionList = false;
  List<Member> _mentionCandidates = []; // 표시용
  final List<Member> _selectedMentions = []; // 전송용
  late int _lastReadAt; // 읽은 마지막 시간
  int _mentionAtIndex = -1; // 멘션 @ 위치 저장
  int _mentionCursorPos = -1; // @ 감지 시점의 커서 위치 저장

  @override
  void initState() {
    super.initState();
    _initCollection();
    _scrollController.addListener(_onScroll);

    // 타이핑
    SendbirdChat.addChannelHandler(
      'typing_${widget.channel.channelUrl}',
      _TypingHandler(
        onUpdate: () => setState(() {}),
        channel: widget.channel,
      ),
    );
  }

  void _initCollection() async {
    _lastReadAt = widget.channel.myReadReceipt();
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
    await _collection.initialize();
    _calculateUnreadDivider();

    // 채팅방 진입 시 읽음 처리 → unreadMessageCount 초기화
    widget.channel.markAsRead();
  }

  // 여기까지 읽음 위치 계산
  int _unreadDividerMessageId = -1;
  void _calculateUnreadDivider() {
    if (_lastReadAt == 0) return;
    if (widget.channel.unreadMessageCount == 0) return;

    final list = _collection.messageList;
    if (list.isEmpty) return;

    for (int i = 0; i < list.length; i++) {
      final msg = list[i];
      if (msg.createdAt <= _lastReadAt) break;
      _unreadDividerMessageId = msg.messageId;
    }
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
    final text = _controller.text;
    if (text.isEmpty) return;
    debugPrint('[Send] mentionedUserIds: ${_selectedMentions.map((e) => e.userId).toList()}');
    _controller.clear();
    widget.channel.endTyping();

    // 메시지 전송
    // 전송 즉시 pending 메시지가 onMessagesAdded로 옴 → UI에 바로 표시
    // 서버 응답 후 succeeded로 변경 → onMessagesUpdated로 교체
    widget.channel.sendUserMessage(
      UserMessageCreateParams(message: text)..mentionedUserIds = _selectedMentions.map((e) => e.userId).toList(),
      handler: (message, error) {
        if (error != null) {
          debugPrint('[Message] 전송 실패: ${error.message}');
          return;
        }
      },
    );
    _selectedMentions.clear();
    setState(() => _showMentionList = false);
  }

  late final _focusNode = FocusNode(
    onKeyEvent: (node, event) {
      if (kIsWeb && event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.enter) {
        if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
        _sendMessage();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
  );

  // 내 메시지 꾹 누르면 수정/삭제 옵션 표시
  // 상대방 메시지 또는 삭제된 메시지는 옵션 없음
  Future<void> _showMessageOptions(BaseMessage msg) async {
    if (msg.customType == 'deleted') return;
    final isMe = msg.sender?.userId == SendbirdChat.currentUser?.userId;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMe)
              ListTile(
                title: const Text('수정'),
                onTap: () {
                  Navigator.pop(context);
                  _showEditDialog(msg as UserMessage);
                },
              ),
            if (isMe)
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
            ListTile(
              title: const Text('리액션'),
              onTap: () {
                Navigator.pop(context);
                _showReactionPicker(msg);
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

  // 이모지
  Future<void> _showReactionPicker(BaseMessage msg) async {
    final emojis = ['👍', '❤️', '😂', '😮', '😢', '😡'];
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: emojis
              .map(
                (emoji) => GestureDetector(
                  onTap: () async {
                    Navigator.pop(context);
                    try {
                      await widget.channel.addReaction(msg, emoji);
                    } catch (e) {
                      debugPrint('[Reaction] 실패: $e');
                    }
                  },
                  child: Text(emoji, style: const TextStyle(fontSize: 24)),
                ),
              )
              .toList(),
        ),
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

    // 마지막 메시지이고 더 불러올 게 없으면 날짜 표시
    if (index + 1 >= list.length) return !_collection.hasPrevious;

    final current = list[index];
    final next = list[index + 1];

    final currentDate = DateTime.fromMillisecondsSinceEpoch(current.createdAt);
    final nextDate = DateTime.fromMillisecondsSinceEpoch(next.createdAt);

    return currentDate.day != nextDate.day || currentDate.month != nextDate.month || currentDate.year != nextDate.year;
  }

  void _selectMention(Member member) {
    final text = _controller.text;
    final after = text.substring(_mentionCursorPos);
    final newText = '${text.substring(0, _mentionAtIndex)}@${member.userId} $after';
    _controller.text = newText;
    final newOffset = (_mentionAtIndex + member.userId.length + 2).clamp(0, newText.length);

    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: newOffset),
    );
    _selectedMentions.add(member);
    setState(() => _showMentionList = false);
  }

  @override
  void dispose() {
    // Collection dispose 필수 - 안 하면 메모리 누수 발생
    _scrollController.dispose();
    _collection.dispose();
    _controller.dispose();
    _focusNode.dispose();
    SendbirdChat.removeChannelHandler('typing_${widget.channel.channelUrl}');
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
                    final isEdited = msg.updatedAt > msg.createdAt;
                    // AdminMessage: 가운데 시스템 메시지로 표시
                    if (msg is AdminMessage) {
                      return Column(
                        children: [
                          if (showDate) _buildDateDivider(msg.createdAt),
                          if (msg.messageId == _unreadDividerMessageId)
                            Center(
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 8),
                                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                                decoration: BoxDecoration(
                                  color: Colors.blue[100],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text('여기까지 읽음', style: TextStyle(fontSize: 12, color: Colors.blue)),
                              ),
                            ),
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
                        if (msg.messageId == _unreadDividerMessageId)
                          Center(
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
                              decoration: BoxDecoration(
                                color: Colors.blue[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Text('여기까지 읽음', style: TextStyle(fontSize: 12, color: Colors.blue)),
                            ),
                          ),
                        GestureDetector(
                          onLongPress: () => _showMessageOptions(msg),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isEdited && !isDeleted)
                                Text('수정됨', style: TextStyle(fontSize: 10, color: Colors.grey)),
                              Flexible(
                                child: Container(
                                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.5),
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
                            ],
                          ),
                        ),
                        Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _buildSendingStatus(msg)),
                        if (msg.reactions != null && msg.reactions!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                            child: Wrap(
                              spacing: 4,
                              children: msg.reactions!.map((reaction) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    '${reaction.key} ${reaction.userIds.length}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
            if (_showMentionList)
              Container(
                constraints: const BoxConstraints(maxHeight: 200),
                margin: EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _mentionCandidates.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final member = _mentionCandidates[index];
                    return ListTile(
                      title: Text(member.userId),
                      onTap: () => _selectMention(member),
                    );
                  },
                ),
              ),
            // 타이핑 인디케이터 여기
            Builder(
              builder: (context) {
                final typingUsers = widget.channel.getTypingUsers();
                if (typingUsers.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Text(
                    '${typingUsers.map((u) => u.userId).join(', ')} 입력 중...',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      focusNode: _focusNode,
                      controller: _controller,
                      textInputAction: TextInputAction.newline,
                      keyboardType: TextInputType.multiline,
                      minLines: 1,
                      maxLines: 6,
                      onChanged: (text) {
                        if (text.isEmpty) {
                          widget.channel.endTyping();
                        } else {
                          widget.channel.startTyping();
                        }

                        // 커서 위치 기준으로 @ 감지
                        // _controller.selection.baseOffset: 현재 커서 위치 (인덱스)
                        final cursorPos = _controller.selection.baseOffset;
                        if (cursorPos == -1) {
                          setState(() => _showMentionList = false);
                          return;
                        }

                        // 커서 앞 텍스트에서만 @ 찾기
                        final textBeforeCursor = text.substring(0, cursorPos);
                        final lastAtIndex = textBeforeCursor.lastIndexOf('@');
                        _mentionAtIndex = lastAtIndex;
                        _mentionCursorPos = cursorPos;

                        if (lastAtIndex != -1) {
                          // @ 앞이 문장 시작이거나 공백일 때만 멘션으로 처리
                          // "hello@world" → 멘션 아님, "hello @world" → 멘션
                          final beforeAt =
                              lastAtIndex == 0 ||
                              textBeforeCursor[lastAtIndex - 1] == ' ' ||
                              textBeforeCursor[lastAtIndex - 1] == '\n';
                          if (beforeAt) {
                            // @ 뒤 텍스트를 query로 사용
                            final query = textBeforeCursor.substring(lastAtIndex + 1).toLowerCase();
                            // query에 공백 포함되면 멘션 선택 완료 → 목록 닫기
                            // "@user " → 선택 완료, "@use" → 입력 중
                            if (!query.contains(' ')) {
                              setState(() {
                                _mentionCandidates = widget.channel.members
                                    .where((m) => m.userId.toLowerCase().contains(query))
                                    .toList();
                                _showMentionList = _mentionCandidates.isNotEmpty;
                              });
                              return;
                            }
                          }
                        }
                        setState(() => _showMentionList = false);
                      },
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
    channel.markAsRead();
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

String _formatTime(int timestamp) {
  final dt = DateTime.fromMillisecondsSinceEpoch(timestamp);
  final month = dt.month.toString().padLeft(2, '0');
  final day = dt.day.toString().padLeft(2, '0');
  final hour = dt.hour.toString().padLeft(2, '0');
  final minute = dt.minute.toString().padLeft(2, '0');

  // 테스트를 위해 [월/일 시:분] 형태로 출력
  return '$month/$day $hour:$minute';
}

class _TypingHandler extends GroupChannelHandler {
  final VoidCallback onUpdate;
  final GroupChannel channel;

  _TypingHandler({required this.onUpdate, required this.channel});

  @override
  void onTypingStatusUpdated(GroupChannel ch) {
    if (ch.channelUrl == channel.channelUrl) onUpdate();
  }

  @override
  void onMessageReceived(BaseChannel channel, BaseMessage message) {
    // MessageCollection이 처리하므로 비워둬도 됨
  }
}
