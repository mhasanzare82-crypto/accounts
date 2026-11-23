import 'dart:async';
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
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF10A37F),
            brightness: Brightness.light,
          ),
          useMaterial3: true,
        ),
        home: const WebTabsHomePage(),
      );
}

class _TabConfig {
  const _TabConfig({required this.name, required this.url});
  final String name;
  final String url;

  _TabConfig copyWith({String? name, String? url}) =>
      _TabConfig(name: name ?? this.name, url: url ?? this.url);

  Map<String, String> toMap() => {'name': name, 'url': url};

  static _TabConfig fromMap(dynamic value, int index) {
    final map = value is Map ? value : const {};
    return _TabConfig(
      name: (map['name'] ?? 'صفحه ${index + 1}').toString(),
      url: (map['url'] ?? 'https://chatgpt.com/').toString(),
    );
  }
}

const _profileNames = [
  'web_tab_profile_one',
  'web_tab_profile_two',
  'web_tab_profile_three',
];

const _defaultConfigs = [
  _TabConfig(name: 'صفحه اول', url: 'https://chatgpt.com/'),
  _TabConfig(name: 'صفحه دوم', url: 'https://chatgpt.com/'),
  _TabConfig(name: 'صفحه سوم', url: 'https://chatgpt.com/'),
];

bool _isValidHttpsUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  return uri != null &&
      uri.scheme.toLowerCase() == 'https' &&
      uri.host.isNotEmpty &&
      uri.userInfo.isEmpty;
}

class WebTabsHomePage extends StatefulWidget {
  const WebTabsHomePage({super.key});

  @override
  State<WebTabsHomePage> createState() => _WebTabsHomePageState();
}

class _WebTabsHomePageState extends State<WebTabsHomePage>
    with WidgetsBindingObserver {
  static const _channel =
      MethodChannel('com.example.chatgpt_accounts/profiles');

  int _selectedIndex = 0;
  List<_TabConfig> _configs = List<_TabConfig>.from(_defaultConfigs);
  late final List<Widget?> _webViews;
  late final List<TextEditingController> _nameControllers;
  late final List<TextEditingController> _urlControllers;
  bool _loading = true;
  bool _saving = false;
  bool _profilesSupported = true;
  bool _microphoneGranted = false;
  bool _checkingMicrophone = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _webViews = List<Widget?>.generate(
      3,
      (index) => index == 0 ? _createWebView(index) : null,
    );
    _nameControllers = List.generate(
      3,
      (index) => TextEditingController(text: _configs[index].name),
    );
    _urlControllers = List.generate(
      3,
      (index) => TextEditingController(text: _configs[index].url),
    );
    _loadSettings();
    _checkProfileSupport();
    _refreshMicrophonePermission();
  }

  Future<void> _loadSettings() async {
    try {
      final saved = await _channel.invokeMethod<List<dynamic>>('getTabConfigs');
      if (saved != null && saved.length == 3) {
        final loaded = List.generate(
          3,
          (index) => _TabConfig.fromMap(saved[index], index),
        );
        if (loaded.every((c) => c.name.trim().isNotEmpty && _isValidHttpsUrl(c.url))) {
          _configs = loaded;
          for (var i = 0; i < 3; i++) {
            _nameControllers[i].text = loaded[i].name;
            _urlControllers[i].text = loaded[i].url;
            // The first WebView is created before persisted settings finish loading.
            // Navigate it to its saved URL so the previous URL is never left visible.
            if (_webViews[i] != null) {
              await _channel.invokeMethod<bool>('loadAccountUrl', {
                'profileName': _profileNames[i],
                'url': loaded[i].url,
              });
            }
          }
        }
      }
    } catch (_) {
      _showMessage('بارگذاری تنظیمات انجام نشد.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkProfileSupport() async {
    try {
      final supported =
          await _channel.invokeMethod<bool>('isMultiProfileSupported') ?? false;
      if (mounted) setState(() => _profilesSupported = supported);
    } catch (_) {
      if (mounted) setState(() => _profilesSupported = false);
    }
  }

  Future<void> _refreshMicrophonePermission() async {
    try {
      final granted =
          await _channel.invokeMethod<bool>('hasMicrophonePermission') ?? false;
      if (mounted) {
        setState(() {
          _microphoneGranted = granted;
          _checkingMicrophone = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checkingMicrophone = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshMicrophonePermission();
  }

  Widget _createWebView(int index) {
    return _AccountWebView(
      key: ValueKey(_profileNames[index]),
      profileName: _profileNames[index],
      initialUrl: _configs[index].url,
    );
  }

  void _selectTab(int index) {
    if (index < 0 || index > 2 || index == _selectedIndex) return;
    setState(() {
      if (index < 3) _webViews[index] ??= _createWebView(index);
      _selectedIndex = index;
    });
  }

  Future<void> _saveSettings() async {
    if (_saving) return;
    final updated = <_TabConfig>[];
    for (var i = 0; i < 3; i++) {
      final name = _nameControllers[i].text.trim();
      final url = _urlControllers[i].text.trim();
      if (name.isEmpty) {
        _showMessage('نام تب ${i + 1} را وارد کن.');
        return;
      }
      if (!_isValidHttpsUrl(url)) {
        _showMessage('لینک تب ${i + 1} معتبر نیست؛ آدرس باید با https:// شروع شود.');
        return;
      }
      updated.add(_TabConfig(name: name, url: Uri.parse(url).toString()));
    }

    setState(() => _saving = true);
    var saved = false;
    try {
      saved = await _channel.invokeMethod<bool>(
            'saveTabConfigs',
            {'tabs': updated.map((config) => config.toMap()).toList()},
          ) ??
          false;
      if (saved) {
        for (var i = 0; i < 3; i++) {
          if (_webViews[i] != null) {
            await _channel.invokeMethod<bool>('loadAccountUrl', {
              'profileName': _profileNames[i],
              'url': updated[i].url,
            });
          }
        }
      }
    } catch (_) {
      saved = false;
    }

    if (!mounted) return;
    setState(() {
      _saving = false;
      if (saved) _configs = updated;
    });
    _showMessage(saved
        ? 'تنظیمات ذخیره شد و صفحات به‌روزرسانی شدند.'
        : 'ذخیره تنظیمات انجام نشد؛ دوباره تلاش کن.');
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.82,
          child: _SettingsPage(
            nameControllers: _nameControllers,
            urlControllers: _urlControllers,
            saving: _saving,
            microphoneGranted: _microphoneGranted,
            checkingMicrophone: _checkingMicrophone,
            onSave: _saveSettings,
          ),
        ),
      ),
    );
  }

  Future<void> _refreshSelectedTab() async {
    if (_selectedIndex > 2) return;
    try {
      await _channel.invokeMethod<bool>('reloadAccount', {
        'profileName': _profileNames[_selectedIndex],
      });
    } catch (_) {
      _showMessage('بارگذاری دوباره صفحه انجام نشد.');
    }
  }

  Future<void> _handleBack() async {
    try {
      final wentBack = await _channel.invokeMethod<bool>('handleBack', {
        'profileName': _profileNames[_selectedIndex],
      });
      if (wentBack != true && mounted) {
        _showMessage('برای خروج، دوباره دکمه بازگشت را لمس کن.');
      }
    } catch (_) {}
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, textDirection: TextDirection.rtl)),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final controller in _nameControllers) {
      controller.dispose();
    }
    for (final controller in _urlControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _handleBack();
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              _configs[_selectedIndex].name,
            ),
            centerTitle: true,
            actions: [
              IconButton(
                tooltip: 'تنظیمات تب‌ها',
                onPressed: _openSettings,
                icon: const Icon(Icons.settings),
              ),
              IconButton(
                tooltip: 'بارگذاری دوباره',
                onPressed: _refreshSelectedTab,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : IndexedStack(
                  index: _selectedIndex,
                  children: [
                    for (var i = 0; i < 3; i++)
                      _profilesSupported
                          ? (_webViews[i] ?? const SizedBox.shrink())
                          : const _UnsupportedProfilesMessage(),
                  ],
                ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: _selectTab,
            destinations: [
              for (var i = 0; i < 3; i++)
                NavigationDestination(
                  icon: const Icon(Icons.language),
                  label: _configs[i].name,
                ),
            ],
          ),
        ),
      );
}

class _SettingsPage extends StatelessWidget {
  const _SettingsPage({
    required this.nameControllers,
    required this.urlControllers,
    required this.saving,
    required this.microphoneGranted,
    required this.checkingMicrophone,
    required this.onSave,
  });

  final List<TextEditingController> nameControllers;
  final List<TextEditingController> urlControllers;
  final bool saving;
  final bool microphoneGranted;
  final bool checkingMicrophone;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'نام و لینک هر تب را مشخص کن. تغییرات پس از ذخیره در حافظه گوشی باقی می‌مانند.',
              style: TextStyle(height: 1.7),
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < 3; i++) ...[
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'تب ${i + 1}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: nameControllers[i],
                        maxLength: 30,
                        decoration: const InputDecoration(
                          labelText: 'نام تب',
                          border: OutlineInputBorder(),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: urlControllers[i],
                        keyboardType: TextInputType.url,
                        textDirection: TextDirection.ltr,
                        decoration: const InputDecoration(
                          labelText: 'لینک صفحه (HTTPS)',
                          hintText: 'https://example.com',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: Text(saving ? 'در حال ذخیره...' : 'ذخیره تنظیمات'),
            ),
            const SizedBox(height: 18),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.mic),
              title: Text('دسترسی میکروفون'),
              subtitle: Text(
                checkingMicrophone
                    ? 'در حال بررسی مجوز میکروفون...'
                    : microphoneGranted
                        ? 'مجوز میکروفون اندروید فعال است. هر سه صفحه HTTPS می‌توانند پس از درخواست سایت از میکروفون استفاده کنند.'
                        : 'مجوز میکروفون هنوز فعال نیست. هنگام درخواست یک صفحه HTTPS، اندروید برای تأیید دسترسی از تو اجازه می‌گیرد.',
              ),
            ),
          ],
        ),
      );
}

class _AccountWebView extends StatelessWidget {
  const _AccountWebView({
    super.key,
    required this.profileName,
    required this.initialUrl,
  });

  final String profileName;
  final String initialUrl;

  @override
  Widget build(BuildContext context) => AndroidView(
        viewType: 'chatgpt/accounts_webview',
        creationParams: <String, String>{
          'profileName': profileName,
          'initialUrl': initialUrl,
        },
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
