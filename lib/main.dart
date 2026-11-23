import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChatGPTAccountsApp());
}

class ChatGPTAccountsApp extends StatelessWidget {
  const ChatGPTAccountsApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'accounts',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF10A37F), brightness: Brightness.light),
      useMaterial3: true,
    ),
    home: const AccountsHomePage(),
  );
}

class _AccountProfile {
  const _AccountProfile({required this.profileName, required this.defaultLabel});
  final String profileName;
  final String defaultLabel;
}
const _accountProfiles = [
  _AccountProfile(profileName: 'chatgpt_account_one', defaultLabel: 'حساب ۱'),
  _AccountProfile(profileName: 'chatgpt_account_two', defaultLabel: 'حساب ۲'),
  _AccountProfile(profileName: 'chatgpt_account_three', defaultLabel: 'حساب ۳'),
  _AccountProfile(profileName: 'chatgpt_account_four', defaultLabel: 'حساب ۴'),
];

class AccountsHomePage extends StatefulWidget {
  const AccountsHomePage({super.key});
  @override
  State<AccountsHomePage> createState() => _AccountsHomePageState();
}
class _AccountsHomePageState extends State<AccountsHomePage> with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.example.chatgpt_accounts/profiles');
  late final Future<bool> _profilesSupported;
  int _selectedIndex = 0;
  late final List<Widget?> _accountViews;
  List<String> _labels = _accountProfiles.map((a) => a.defaultLabel).toList();
  bool _microphoneGranted = false;
  bool _checkingMicrophone = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _profilesSupported = _checkProfileSupport();
    // Create only the first account's platform view. Other WebViews are
    // created on first selection and retained in the IndexedStack thereafter.
    _accountViews = List<Widget?>.generate(
      _accountProfiles.length,
      (index) => index == 0 ? _createAccountView(index) : null,
    );
    _loadLabels();
    _refreshMicrophonePermission();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshMicrophonePermission();
  }

  Future<void> _refreshMicrophonePermission() async {
    try {
      final granted = await _channel.invokeMethod<bool>('hasMicrophonePermission') ?? false;
      if (mounted) setState(() { _microphoneGranted = granted; _checkingMicrophone = false; });
    } catch (_) {
      if (mounted) setState(() => _checkingMicrophone = false);
    }
  }

  Future<void> _requestMicrophonePermission() async {
    try {
      await _channel.invokeMethod<void>('requestMicrophonePermission');
    } on PlatformException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('درخواست مجوز میکروفون انجام نشد.')));
    } on MissingPluginException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('امکان درخواست مجوز در این نسخه وجود ندارد.')));
    }
    await _refreshMicrophonePermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _loadLabels() async {
    try {
      final saved = await _channel.invokeMethod<List<dynamic>>('getAccountLabels');
      if (saved != null && saved.length == 4) {
        final names = saved.map((e) => e.toString().trim()).toList();
        if (names.every((e) => e.isNotEmpty) && mounted) setState(() => _labels = names);
      }
    } catch (_) {}
  }

  Future<bool> _saveLabels(List<String> labels) async {
    try {
      return await _channel.invokeMethod<bool>('saveAccountLabels', {'labels': labels}) ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _rename(int i) async {
    final ctl = TextEditingController(text: _labels[i]);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تغییر نام حساب'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          maxLength: 30,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(labelText: 'نام حساب'),
          onSubmitted: (v) { if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim()); },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لغو')),
          FilledButton(onPressed: () { if (ctl.text.trim().isNotEmpty) Navigator.pop(ctx, ctl.text.trim()); }, child: const Text('ذخیره')),
        ],
      ),
    );
    ctl.dispose();
    if (name == null || name.trim().isEmpty || !mounted) return;
    final updated = List<String>.from(_labels)..[i] = name.trim();
    final saved = await _saveLabels(updated);
    if (!mounted) return;
    if (saved) {
      setState(() => _labels = updated);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ذخیره نام حساب انجام نشد؛ دوباره تلاش کن.')));
    }
  }

  Future<bool> _checkProfileSupport() async {
    try {
      return await _channel.invokeMethod<bool>('isMultiProfileSupported') ?? false;
    } on PlatformException { return false; } on MissingPluginException { return false; }
  }

  Widget _createAccountView(int index) {
    final account = _accountProfiles[index];
    return _AccountWebView(
      key: ValueKey(account.profileName),
      profileName: account.profileName,
    );
  }

  void _selectAccount(int index) {
    if (index < 0 || index >= _accountProfiles.length || index == _selectedIndex) return;
    setState(() {
      _accountViews[index] ??= _createAccountView(index);
      _selectedIndex = index;
    });
  }

  Future<void> _handleBack() async {
    try {
      await _channel.invokeMethod<bool>('handleBack', {'profileName': _accountProfiles[_selectedIndex].profileName});
    } on PlatformException {} on MissingPluginException {}
  }

  Future<void> _refreshSelectedAccount() async {
    try {
      await _channel.invokeMethod<bool>('reloadAccount', {
        'profileName': _accountProfiles[_selectedIndex].profileName,
      });
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('رفرش صفحه انجام نشد. دوباره تلاش کن.')),
        );
      }
    } on MissingPluginException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('قابلیت رفرش در این نسخه در دسترس نیست.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvoked: (didPop) { if (!didPop) _handleBack(); },
    child: Scaffold(
      appBar: AppBar(
        title: Text(_labels[_selectedIndex]),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'رفرش صفحه',
            onPressed: _refreshSelectedAccount,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_checkingMicrophone && !_microphoneGranted)
            Material(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(
                  children: [
                    const Icon(Icons.mic_none),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'برای استفاده از قابلیت گفت‌وگوی صوتی، مجوز میکروفون را فعال کن.',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(height: 1.5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _requestMicrophonePermission,
                      child: const Text('فعال‌سازی'),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: FutureBuilder<bool>(
              future: _profilesSupported,
              builder: (context, s) {
                if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
                if (s.data != true) return const _UnsupportedProfilesMessage();
                return IndexedStack(
                  index: _selectedIndex,
                  children: List<Widget>.generate(
                    _accountProfiles.length,
                    (index) => _accountViews[index] ?? const SizedBox.shrink(),
                    growable: false,
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _AccountNavigationBar(
        labels: _labels,
        selectedIndex: _selectedIndex,
        onSelect: _selectAccount,
        onRename: _rename,
      ),
    ),
  );
}

class _AccountNavigationBar extends StatelessWidget {
  const _AccountNavigationBar({required this.labels, required this.selectedIndex, required this.onSelect, required this.onRename});
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<int> onRename;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    elevation: 3,
    child: SafeArea(
      top: false,
      child: SizedBox(
        height: 68,
        child: Row(
          children: List.generate(4, (i) => Expanded(
            child: _AccountNavigationItem(
              label: labels[i],
              selected: selectedIndex == i,
              onSelect: () => onSelect(i),
              onRename: () => onRename(i),
            ),
          )),
        ),
      ),
    ),
  );
}

class _AccountNavigationItem extends StatefulWidget {
  const _AccountNavigationItem({required this.label, required this.selected, required this.onSelect, required this.onRename});
  final String label;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onRename;
  @override
  State<_AccountNavigationItem> createState() => _AccountNavigationItemState();
}
class _AccountNavigationItemState extends State<_AccountNavigationItem> {
  Timer? _holdTimer;
  bool _renamedByHold = false;

  void _pointerDown(PointerDownEvent event) {
    _holdTimer?.cancel();
    _renamedByHold = false;
    _holdTimer = Timer(const Duration(seconds: 3), () {
      _renamedByHold = true;
      widget.onRename();
    });
  }

  void _pointerUp(PointerEvent event) {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (!_renamedByHold) widget.onSelect();
  }

  void _pointerCancel(PointerEvent event) {
    _holdTimer?.cancel();
    _holdTimer = null;
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = widget.selected ? colorScheme.primary : colorScheme.onSurfaceVariant;
    return Listener(
      onPointerDown: _pointerDown,
      onPointerUp: _pointerUp,
      onPointerCancel: _pointerCancel,
      child: Semantics(
        button: true,
        label: widget.label,
        child: SizedBox.expand(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.account_circle, size: 24, color: color),
                const SizedBox(height: 3),
                Text(widget.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: color)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountWebView extends StatelessWidget {
  const _AccountWebView({super.key, required this.profileName});
  final String profileName;
  @override
  Widget build(BuildContext context) => AndroidView(
    viewType: 'chatgpt/accounts_webview',
    creationParams: <String, String>{'profileName': profileName, 'initialUrl': 'https://chatgpt.com/'},
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
        'نسخه WebView این دستگاه از نشست‌های مستقل پشتیبانی نمی‌کند. برای جلوگیری از ورود اشتباه یا مشترک شدن حساب‌ها، صفحه‌ها باز نشدند. لطفاً Android System WebView یا Chrome را به‌روزرسانی کنید و دوباره برنامه را باز کنید.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, height: 1.8),
      ),
    ),
  );
}
