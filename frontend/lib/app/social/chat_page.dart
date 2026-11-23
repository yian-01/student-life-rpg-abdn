import 'dart:async';
import 'package:flutter/material.dart';
import '../cloud/cloud_scope.dart';
import '../cloud/sync_api.dart';
import 'social_api.dart';
import 'profile_avatar.dart';

class ChatPage extends StatelessWidget {
  const ChatPage({
    super.key,
    required this.session,
    required this.person,
    this.api = const SocialApi(),
  });
  final CloudSession session;
  final Person person;
  final SocialApi api;
  @override
  Widget build(BuildContext context) {
    final cloud = CloudScope.maybeOf(context);
    if (cloud?.session?.id != session.id ||
        cloud?.session?.origin != session.origin ||
        cloud!.expired) {
      return Scaffold(
        appBar: AppBar(title: const Text('私信')),
        body: const Center(child: Text('当前账号已退出，请重新登录。')),
      );
    }
    return _Conversation(
      key: ValueKey(cloud.scope),
      session: session,
      person: person,
      api: api,
    );
  }
}

class _Conversation extends StatefulWidget {
  const _Conversation({
    super.key,
    required this.session,
    required this.person,
    required this.api,
  });
  final CloudSession session;
  final Person person;
  final SocialApi api;
  @override
  State<_Conversation> createState() => _ConversationState();
}

class _ConversationState extends State<_Conversation>
    with WidgetsBindingObserver {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final Map<int, Map<String, dynamic>> _messages = {};
  Timer? _timer;
  bool _loading = false, _sending = false, _hasMore = false, _foreground = true;
  String? _error, _pendingId, _pendingText;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_foreground && ModalRoute.of(context)?.isCurrent == true) {
        _load(quiet: true);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground =
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.detached;
    if (_foreground) _load(quiet: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  String _errorText(Object error) =>
      error is SocialException ? error.message : '暂时无法完成操作，请重试。';
  void _bottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && _scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  });
  Future<void> _load({bool older = false, bool quiet = false}) async {
    if (_loading) return;
    setState(() => _loading = true);
    final atBottom =
        !_scroll.hasClients ||
        _scroll.position.maxScrollExtent - _scroll.offset < 100;
    try {
      final raw = await widget.api.call(
        widget.session,
        'messages',
        query: {
          'id': widget.person.id,
          if (older && _messages.isNotEmpty)
            'before': (_messages.keys.reduce(
              (a, b) => a < b ? a : b,
            )).toString(),
        },
      );
      if (!mounted) return;
      final initial = _messages.isEmpty;
      setState(() {
        for (final item in raw['messages'] as List) {
          final message = item as Map<String, dynamic>;
          _messages[message['id'] as int] = message;
        }
        if (older || initial) _hasMore = raw['hasMore'] as bool;
        if (!_sending && _pendingId == null) _error = null;
      });
      if (!older && atBottom) _bottom();
    } catch (e) {
      if (mounted && (!quiet || _error == null)) {
        setState(() => _error = _errorText(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    if (_sending || _text.text.trim().isEmpty) return;
    if (_text.text.trim().runes.length > 2000) {
      setState(() => _error = '每条私信最多 2000 个字符。');
      return;
    }
    _pendingId ??= SocialApi.messageId();
    _pendingText ??= _text.text.trim();
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.api.call(
        widget.session,
        'messages',
        method: 'POST',
        data: {
          'id': widget.person.id,
          'clientId': _pendingId,
          'text': _pendingText,
        },
      );
      if (!mounted) return;
      _pendingId = _pendingText = null;
      _text.clear();
      await _load();
      _bottom();
    } catch (e) {
      if (mounted) setState(() => _error = _errorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordered = _messages.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ProfileAvatar(widget.person.avatar, size: 28),
            const SizedBox(width: 12),
            Expanded(child: Text(widget.person.nickname)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            tooltip: '刷新私信',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 820),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'ID ${widget.person.id} · 仅好友可收发私信',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              if (_loading) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Semantics(liveRegion: true, child: Text(_error!)),
                ),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_hasMore)
                      Center(
                        child: TextButton(
                          onPressed: _loading ? null : () => _load(older: true),
                          child: const Text('加载更早的消息'),
                        ),
                      ),
                    if (ordered.isEmpty && !_loading)
                      const Center(child: Text('从一句问候开始吧。')),
                    for (final id in ordered) _message(_messages[id]!),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: _text,
                        enabled: !_sending,
                        readOnly: _pendingId != null,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 2000,
                        decoration: const InputDecoration(
                          labelText: '输入私信',
                          hintText: '写点什么…',
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (_pendingId != null && !_sending)
                            TextButton(
                              onPressed: () => setState(() {
                                _pendingId = _pendingText = null;
                              }),
                              child: const Text('返回编辑'),
                            ),
                          FilledButton(
                            onPressed: _sending ? null : _send,
                            child: Text(
                              _sending
                                  ? '发送中…'
                                  : _pendingId != null
                                  ? '重试发送'
                                  : '发送',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _message(Map<String, dynamic> message) {
    final mine = message['mine'] as bool;
    final date = DateTime.fromMillisecondsSinceEpoch(
      (message['createdAt'] as int) * 1000,
    ).toLocal();
    final stamp =
        '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 560),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: mine
              ? Theme.of(context).colorScheme.primary.withValues(alpha: .12)
              : Theme.of(context).colorScheme.onSurface.withValues(alpha: .04),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              message['text'] as String,
              semanticsLabel: message['text'] as String,
            ),
            const SizedBox(height: 4),
            Text(stamp, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
