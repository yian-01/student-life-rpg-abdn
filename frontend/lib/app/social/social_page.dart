import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../cloud/cloud_scope.dart';
import '../cloud/cloud_page.dart';
import '../cloud/sync_api.dart';
import 'social_api.dart';
import 'profile_avatar.dart';
import 'chat_page.dart';

class SocialPage extends StatelessWidget {
  const SocialPage({super.key, this.api = const SocialApi()});
  static const route = '/people';
  final SocialApi api;
  @override
  Widget build(BuildContext context) {
    final cloud = CloudScope.maybeOf(context);
    final session = cloud?.session;
    if (session == null || cloud!.expired) {
      return Scaffold(
        appBar: AppBar(title: const Text('个人空间')),
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pushNamed(CloudPage.route),
            child: const Text('登录后查看个人空间'),
          ),
        ),
      );
    }
    return _Space(key: ValueKey(cloud.scope), session: session, api: api);
  }
}

class _Space extends StatefulWidget {
  const _Space({super.key, required this.session, required this.api});
  final CloudSession session;
  final SocialApi api;
  @override
  State<_Space> createState() => _SpaceState();
}

class _SpaceState extends State<_Space> {
  Person? _me, _found;
  List<Person> _friends = [], _incoming = [], _outgoing = [];
  final _search = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is SocialException ? e.message : '暂时无法读取资料，请重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() async {
    final values = await Future.wait([
      widget.api.call(widget.session, 'profile'),
      widget.api.call(widget.session, 'friends'),
      widget.api.call(widget.session, 'friend-requests'),
    ]);
    if (!mounted) return;
    setState(() {
      _me = Person.decode(values[0]);
      _friends = SocialApi.people(values[1]['friends']);
      _incoming = SocialApi.people(values[2]['incoming']);
      _outgoing = SocialApi.people(values[2]['outgoing']);
    });
  }

  Future<void> _refresh() => _run(_load);
  Future<void> _change(String path, String method, Person person) =>
      _run(() async {
        await widget.api.call(
          widget.session,
          path,
          method: method,
          data: {'id': person.id},
        );
        await _load();
      });
  Future<void> _searchPerson() => _run(() async {
    setState(() => _found = null);
    final value = await widget.api.call(
      widget.session,
      'people',
      query: {'id': _search.text.trim()},
    );
    if (mounted) setState(() => _found = Person.decode(value));
  });
  void _chat(Person person) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        settings: const RouteSettings(name: '/people/chat'),
        builder: (_) =>
            ChatPage(session: widget.session, person: person, api: widget.api),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 3,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('个人空间'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _refresh,
            tooltip: '刷新个人空间',
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: TabBar(
          tabs: [
            const Tab(text: '个人资料'),
            Tab(text: '好友 · ${_friends.length}'),
            Tab(text: '申请 · ${_incoming.length}'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Semantics(liveRegion: true, child: Text(_error!)),
            ),
          Expanded(
            child: _me == null
                ? Center(
                    child: _busy
                        ? const Text('正在打开你的空间…')
                        : TextButton(
                            onPressed: _refresh,
                            child: const Text('重新加载'),
                          ),
                  )
                : TabBarView(
                    children: [
                      _ProfileEditor(
                        person: _me!,
                        busy: _busy,
                        save: (value) => _run(() async {
                          final raw = await widget.api.call(
                            widget.session,
                            'profile',
                            method: 'PUT',
                            data: value,
                          );
                          if (mounted && context.mounted) {
                            setState(() => _me = Person.decode(raw));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('个人资料已保存')),
                            );
                          }
                        }),
                      ),
                      ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          const Text(
                            '认识新的课屿居民',
                            style: TextStyle(fontSize: 18),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _search,
                            maxLength: 10,
                            textCapitalization: TextCapitalization.characters,
                            decoration: const InputDecoration(
                              labelText: '好友 ID',
                              hintText: '输入对方的 10 位 ID',
                            ),
                            onSubmitted: (_) => _searchPerson(),
                          ),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: _busy ? null : _searchPerson,
                              child: const Text('查找好友'),
                            ),
                          ),
                          if (_found != null)
                            _person(
                              _found!,
                              actions: [
                                TextButton(
                                  onPressed:
                                      _busy ||
                                          _found!.id == _me!.id ||
                                          _friends.any(
                                            (p) => p.id == _found!.id,
                                          ) ||
                                          _outgoing.any(
                                            (p) => p.id == _found!.id,
                                          )
                                      ? null
                                      : () =>
                                            _change('friends', 'POST', _found!),
                                  child: Text(
                                    _outgoing.any((p) => p.id == _found!.id)
                                        ? '已申请'
                                        : '添加好友',
                                  ),
                                ),
                              ],
                            ),
                          const Divider(height: 36),
                          if (_friends.isEmpty)
                            const Text('还没有好友。分享你的 ID，或输入朋友的 ID 发出申请。'),
                          for (final person in _friends)
                            _person(
                              person,
                              actions: [
                                TextButton(
                                  onPressed: _busy ? null : () => _chat(person),
                                  child: const Text('私信'),
                                ),
                                IconButton(
                                  tooltip: '移除好友',
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          final remove = await showDialog<bool>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: const Text('移除好友？'),
                                              content: Text(
                                                '移除 ${person.nickname} 后将停止收发彼此的私信。',
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        context,
                                                        false,
                                                      ),
                                                  child: const Text('取消'),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        context,
                                                        true,
                                                      ),
                                                  child: const Text('移除'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (remove == true && mounted) {
                                            await _change(
                                              'friends',
                                              'DELETE',
                                              person,
                                            );
                                          }
                                        },
                                  icon: const Icon(
                                    Icons.person_remove_outlined,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          const Text('收到的申请', style: TextStyle(fontSize: 18)),
                          if (_incoming.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text('暂时没有新的好友申请。'),
                            ),
                          for (final person in _incoming)
                            _person(
                              person,
                              actions: [
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _change(
                                          'friend-requests',
                                          'POST',
                                          person,
                                        ),
                                  child: const Text('接受'),
                                ),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _change(
                                          'friend-requests',
                                          'DELETE',
                                          person,
                                        ),
                                  child: const Text('拒绝'),
                                ),
                              ],
                            ),
                          const Divider(height: 36),
                          const Text('发出的申请', style: TextStyle(fontSize: 18)),
                          if (_outgoing.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text('没有待处理的申请。'),
                            ),
                          for (final person in _outgoing)
                            _person(
                              person,
                              actions: [
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _change(
                                          'friend-requests',
                                          'DELETE',
                                          person,
                                        ),
                                  child: const Text('撤回'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  );

  Widget _person(Person p, {required List<Widget> actions}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileAvatar(p.avatar, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.nickname, style: const TextStyle(fontSize: 16)),
              SelectableText(
                'ID ${p.id}',
                semanticsLabel: 'ID ${p.id}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (p.bio.isNotEmpty)
                Text(p.bio, maxLines: 2, overflow: TextOverflow.ellipsis),
              Wrap(children: actions),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ProfileEditor extends StatefulWidget {
  const _ProfileEditor({
    required this.person,
    required this.busy,
    required this.save,
  });
  final Person person;
  final bool busy;
  final Future<void> Function(Map<String, dynamic>) save;
  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  final _form = GlobalKey<FormState>();
  late final _nickname = TextEditingController(text: widget.person.nickname);
  late final _bio = TextEditingController(text: widget.person.bio);
  late final _title = TextEditingController(text: widget.person.title);
  late String _avatar = widget.person.avatar;
  @override
  void dispose() {
    _nickname.dispose();
    _bio.dispose();
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProfileAvatar(_avatar, size: 80),
                const SizedBox(height: 16),
                Text(
                  widget.person.nickname,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  'ID ${widget.person.id}',
                  semanticsLabel: 'ID ${widget.person.id}',
                ),
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(
                      ClipboardData(text: widget.person.id),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(const SnackBar(content: Text('ID 已复制')));
                    }
                  },
                  child: const Text('复制我的 ID'),
                ),
                const Text('这个 ID 用于添加好友，邮箱只用于登录，不会展示给其他用户。'),
                const SizedBox(height: 24),
                DropdownButtonFormField<String>(
                  initialValue: _avatar,
                  decoration: const InputDecoration(labelText: '像素头像'),
                  items: [
                    for (final entry in profileAvatars.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: widget.busy
                      ? null
                      : (v) => setState(() => _avatar = v!),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nickname,
                  enabled: !widget.busy,
                  maxLength: 24,
                  decoration: const InputDecoration(labelText: '昵称'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请填写昵称' : null,
                ),
                TextFormField(
                  controller: _title,
                  enabled: !widget.busy,
                  maxLength: 20,
                  decoration: const InputDecoration(
                    labelText: '个人称号',
                    hintText: '例如：星夜旅人',
                  ),
                ),
                TextFormField(
                  controller: _bio,
                  enabled: !widget.busy,
                  maxLength: 200,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: '个人简介'),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: widget.busy
                      ? null
                      : () {
                          if (_form.currentState!.validate()) {
                            widget.save({
                              'nickname': _nickname.text.trim(),
                              'avatar': _avatar,
                              'bio': _bio.text.trim(),
                              'title': _title.text.trim(),
                            });
                          }
                        },
                  child: const Text('保存个人资料'),
                ),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}
