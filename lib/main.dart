import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const WebTabsApp());
}

class WebTabsApp extends StatelessWidget {
  const WebTabsApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'مدیریت صفحات وب',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF10A37F)),
          useMaterial3: true,
        ),
        home: const WebTabsHomePage(),
      );
}

class _TabConfig {
  const _TabConfig({
    required this.id,
    required this.name,
    required this.url,
    this.lastUrl = '',
  });
  final String id;
  final String name;
  final String url;
  final String lastUrl;

  _TabConfig copyWith({String? name, String? url}) => _TabConfig(
        id: id,
        name: name ?? this.name,
        url: url ?? this.url,
        lastUrl: lastUrl,
      );

  Map<String, String> toMap() => {'id': id, 'name': name, 'url': url};

  static _TabConfig fromMap(dynamic value, int index) {
    final map = value is Map ? value : const {};
    return _TabConfig(
      id: (map['id'] ?? ('web_tab_profile_' + (index + 1).toString())).toString(),
      name: (map['name'] ?? ('صفحه ' + (index + 1).toString())).toString(),
      url: (map['url'] ?? 'https://chatgpt.com/').toString(),
      lastUrl: (map['lastUrl'] ?? '').toString(),
    );
  }
}

const _defaults = [
  _TabConfig(id: 'web_tab_profile_one', name: 'صفحه اول', url: 'https://chatgpt.com/'),
  _TabConfig(id: 'web_tab_profile_two', name: 'صفحه دوم', url: 'https://chatgpt.com/'),
  _TabConfig(id: 'web_tab_profile_three', name: 'صفحه سوم', url: 'https://chatgpt.com/'),
];

bool _validUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null && uri.scheme.toLowerCase() == 'https' &&
      uri.host.isNotEmpty && uri.userInfo.isEmpty;
}

String _newId() => 'account_' +
    DateTime.now().microsecondsSinceEpoch.toString() +
    '_' +
    Random.secure().nextInt(1 << 32).toString();

class WebTabsHomePage extends StatefulWidget {
  const WebTabsHomePage({super.key});
  @override
  State<WebTabsHomePage> createState() => _WebTabsHomePageState();
}

class _WebTabsHomePageState extends State<WebTabsHomePage>
    with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.example.chatgpt_accounts/profiles');
  List<_TabConfig> _tabs = List<_TabConfig>.from(_defaults);
  final Map<String, Widget> _views = {};
  int _selected = 0;
  bool _loading = true;
  bool _saving = false;
  bool _profilesSupported = true;
  bool _micGranted = false;
  bool _checkingMic = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _checkProfiles();
    _checkMic();
  }

  Future<void> _load() async {
    try {
      final values = await _channel.invokeMethod<List<dynamic>>('getTabConfigs');
      if (values != null && values.isNotEmpty) {
        final loaded = List.generate(values.length, (i) => _TabConfig.fromMap(values[i], i));
        if (loaded.every((t) => t.id.isNotEmpty && t.name.trim().isNotEmpty && _validUrl(t.url))) {
          _tabs = loaded;
        }
      }
    } catch (_) {
      _message('بارگذاری تنظیمات انجام نشد.');
    } finally {
      if (mounted) {
        _views.putIfAbsent(_tabs[_selected].id, () => _viewFor(_tabs[_selected]));
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _checkProfiles() async {
    try {
      final ok = await _channel.invokeMethod<bool>('isMultiProfileSupported') ?? false;
      if (mounted) setState(() => _profilesSupported = ok);
    } catch (_) {
      if (mounted) setState(() => _profilesSupported = false);
    }
  }

  Future<void> _checkMic() async {
    try {
      final ok = await _channel.invokeMethod<bool>('hasMicrophonePermission') ?? false;
      if (mounted) setState(() { _micGranted = ok; _checkingMic = false; });
    } catch (_) {
      if (mounted) setState(() => _checkingMic = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkMic();
  }

  Widget _viewFor(_TabConfig tab) => _AccountWebView(
        key: ValueKey(tab.id),
        profileName: tab.id,
        initialUrl: _validUrl(tab.lastUrl) ? tab.lastUrl : tab.url,
      );

  void _select(int index) {
    if (index < 0 || index >= _tabs.length) return;
    setState(() {
      _views.putIfAbsent(_tabs[index].id, () => _viewFor(_tabs[index]));
      _selected = index;
    });
  }

  Future<bool> _save(List<_TabConfig> next) async {
    if (_saving) return false;
    if (next.isEmpty) {
      _message('حداقل یک تب باید باقی بماند.');
      return false;
    }
    if (next.map((t) => t.id).toSet().length != next.length) {
      _message('شناسه تب‌ها تکراری است.');
      return false;
    }
    for (var i = 0; i < next.length; i++) {
      if (next[i].name.trim().isEmpty) {
        _message('نام تب ' + (i + 1).toString() + ' را وارد کن.');
        return false;
      }
      if (!_validUrl(next[i].url)) {
        _message('آدرس تب ' + (i + 1).toString() + ' باید HTTPS معتبر باشد.');
        return false;
      }
    }

    setState(() => _saving = true);
    var ok = false;
    try {
      ok = await _channel.invokeMethod<bool>(
            'saveTabConfigs',
            {'tabs': next.map((t) => t.toMap()).toList()},
          ) ?? false;
      if (ok) {
        for (final tab in next) {
          if (_views.containsKey(tab.id)) {
            await _channel.invokeMethod<bool>('loadAccountUrl', {
              'profileName': tab.id,
              'url': Uri.parse(tab.url.trim()).toString(),
            });
          }
        }
      }
    } catch (_) {
      ok = false;
    }

    if (!mounted) return false;
    if (ok) {
      final selectedId = _tabs[_selected].id;
      final newIds = next.map((t) => t.id).toSet();
      _views.removeWhere((id, view) => !newIds.contains(id));
      setState(() {
        _tabs = next.map((t) => t.copyWith(url: Uri.parse(t.url.trim()).toString())).toList();
        final preservedIndex = _tabs.indexWhere((tab) => tab.id == selectedId);
        if (preservedIndex >= 0) {
          _selected = preservedIndex;
        } else if (_selected >= _tabs.length) {
          _selected = _tabs.length - 1;
        }
        _saving = false;
      });
      _message('تب‌ها و تنظیمات ذخیره شدند.');
      return true;
    } else {
      setState(() => _saving = false);
      _message('ذخیره تنظیمات انجام نشد.');
      return false;
    }
  }

  void _settings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * .88,
          child: _SettingsPage(
            initial: _tabs,
            saving: _saving,
            micGranted: _micGranted,
            checkingMic: _checkingMic,
            onSave: _save,
          ),
        ),
      ),
    );
  }

  Future<void> _reload() async {
    if (_tabs.isEmpty) return;
    try {
      await _channel.invokeMethod<bool>('reloadAccount', {'profileName': _tabs[_selected].id});
    } catch (_) {
      _message('بارگذاری دوباره صفحه انجام نشد.');
    }
  }

  Future<void> _back() async {
    if (_tabs.isEmpty) return;
    try {
      final result = await _channel.invokeMethod<bool>(
        'handleBack',
        {'profileName': _tabs[_selected].id},
      );
      if (result != true && mounted) _message('برای خروج، دوباره دکمه بازگشت را لمس کن.');
    } catch (_) {}
  }

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value, textDirection: TextDirection.rtl)),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) { if (!didPop) _back(); },
        child: Scaffold(
          appBar: AppBar(
            title: Text(_tabs.isEmpty ? 'مدیریت صفحات وب' : _tabs[_selected].name),
            centerTitle: true,
            actions: [
              IconButton(tooltip: 'تنظیمات تب‌ها', onPressed: _settings, icon: const Icon(Icons.settings)),
              IconButton(tooltip: 'بارگذاری دوباره', onPressed: _reload, icon: const Icon(Icons.refresh)),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : !_profilesSupported
                  ? const _UnsupportedProfilesMessage()
                  : IndexedStack(
                      index: _selected,
                      children: [
                        for (final tab in _tabs)
                          _views[tab.id] ?? const SizedBox.shrink(),
                      ],
                    ),
          bottomNavigationBar: _loading || !_profilesSupported
              ? null
              : SafeArea(
                  top: false,
                  child: SizedBox(
                    height: 66,
                    child: Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            reverse: true,
                            child: Row(
                              children: [
                                for (var i = 0; i < _tabs.length; i++)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                                    child: ChoiceChip(
                                      label: Text(_tabs[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      selected: i == _selected,
                                      onSelected: (_) => _select(i),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'افزودن تب',
                          onPressed: _settings,
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                  ),
                ),
        ),
      );
}

class _SettingsPage extends StatefulWidget {
  const _SettingsPage({
    required this.initial,
    required this.saving,
    required this.micGranted,
    required this.checkingMic,
    required this.onSave,
  });
  final List<_TabConfig> initial;
  final bool saving;
  final bool micGranted;
  final bool checkingMic;
  final Future<bool> Function(List<_TabConfig>) onSave;

  @override
  State<_SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<_SettingsPage> {
  late List<_TabConfig> _tabs;
  late List<TextEditingController> _names;
  late List<TextEditingController> _urls;

  @override
  void initState() {
    super.initState();
    _tabs = List<_TabConfig>.from(widget.initial);
    _names = _tabs.map((t) => TextEditingController(text: t.name)).toList();
    _urls = _tabs.map((t) => TextEditingController(text: t.url)).toList();
  }

  void _add() {
    final tab = _TabConfig(id: _newId(), name: 'صفحه ' + (_tabs.length + 1).toString(), url: 'https://chatgpt.com/');
    setState(() {
      _tabs.add(tab);
      _names.add(TextEditingController(text: tab.name));
      _urls.add(TextEditingController(text: tab.url));
    });
  }

  void _remove(int index) {
    if (_tabs.length <= 1) return;
    setState(() {
      _tabs.removeAt(index);
      _names.removeAt(index).dispose();
      _urls.removeAt(index).dispose();
    });
  }

  Future<void> _save() async {
    final result = <_TabConfig>[];
    for (var i = 0; i < _tabs.length; i++) {
      result.add(_tabs[i].copyWith(name: _names[i].text.trim(), url: _urls[i].text.trim()));
    }
    final saved = await widget.onSave(result);
    if (mounted && saved) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    for (final c in _names) { c.dispose(); }
    for (final c in _urls) { c.dispose(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'هر تب حساب مستقلی دارد. کوکی‌ها و داده‌های نشست هر حساب در پروفایل جداگانه همان تب نگهداری می‌شود و پس از اجرای دوباره برنامه قابل بازیابی است.',
              style: TextStyle(height: 1.8),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < _tabs.length; i++) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('تب ' + (i + 1).toString(), style: Theme.of(context).textTheme.titleMedium)),
                          IconButton(
                            tooltip: 'حذف تب',
                            onPressed: _tabs.length <= 1 ? null : () => _remove(i),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                      TextField(
                        controller: _names[i],
                        maxLength: 30,
                        decoration: const InputDecoration(labelText: 'نام تب', border: OutlineInputBorder(), counterText: ''),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _urls[i],
                        keyboardType: TextInputType.url,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(labelText: 'آدرس شروع (HTTPS)', hintText: 'https://example.com', border: OutlineInputBorder()),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('افزودن تب جدید')),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: widget.saving ? null : _save,
              icon: widget.saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: Text(widget.saving ? 'در حال ذخیره...' : 'ذخیره تغییرات'),
            ),
            const SizedBox(height: 18),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.mic),
              title: const Text('دسترسی میکروفون'),
              subtitle: Text(widget.checkingMic ? 'در حال بررسی...' : widget.micGranted ? 'مجوز میکروفون فعال است.' : 'در صورت درخواست صفحه HTTPS، اندروید برای تأیید دسترسی اجازه می‌گیرد.'),
            ),
            const SizedBox(height: 8),
            const Text(
              'برنامه رمز عبور را به‌صورت متن ساده ذخیره نمی‌کند. ماندگاری ورود از طریق کوکی‌ها و داده‌های سایت در پروفایل مستقل Android WebView انجام می‌شود. اگر سایت نشست را منقضی کند یا تأیید دوباره بخواهد، ورود مجدد لازم است.',
              style: TextStyle(height: 1.7, fontSize: 12),
            ),
          ],
        ),
      );
}

class _AccountWebView extends StatelessWidget {
  const _AccountWebView({super.key, required this.profileName, required this.initialUrl});
  final String profileName;
  final String initialUrl;
  @override
  Widget build(BuildContext context) => AndroidView(
        viewType: 'chatgpt/accounts_webview',
        creationParams: {'profileName': profileName, 'initialUrl': initialUrl},
        creationParamsCodec: const StandardMessageCodec(),
      );
}

class _UnsupportedProfilesMessage extends StatelessWidget {
  const _UnsupportedProfilesMessage();
  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'نسخه Android System WebView این دستگاه از پروفایل‌های مستقل پشتیبانی نمی‌کند. برای جلوگیری از اشتراک کوکی‌ها، صفحات باز نشدند. لطفاً Android System WebView یا Chrome را به‌روزرسانی کن.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.8),
          ),
        ),
      );
}
