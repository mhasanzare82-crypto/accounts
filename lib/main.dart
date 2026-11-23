import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChatGPTAccountsApp());
}

class ChatGPTAccountsApp extends StatelessWidget {
  const ChatGPTAccountsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'accounts',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF10A37F),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const AccountsHomePage(),
    );
  }
}

class _AccountProfile {
  const _AccountProfile({
    required this.label,
    required this.profileName,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final String profileName;
  final IconData icon;
  final IconData selectedIcon;
}

const List<_AccountProfile> _accountProfiles = [
  _AccountProfile(
    label: 'حساب ۱',
    profileName: 'chatgpt_account_one',
    icon: Icons.account_circle_outlined,
    selectedIcon: Icons.account_circle,
  ),
  _AccountProfile(
    label: 'حساب ۲',
    profileName: 'chatgpt_account_two',
    icon: Icons.account_circle_outlined,
    selectedIcon: Icons.account_circle,
  ),
  _AccountProfile(
    label: 'حساب ۳',
    profileName: 'chatgpt_account_three',
    icon: Icons.account_circle_outlined,
    selectedIcon: Icons.account_circle,
  ),
  _AccountProfile(
    label: 'حساب ۴',
    profileName: 'chatgpt_account_four',
    icon: Icons.account_circle_outlined,
    selectedIcon: Icons.account_circle,
  ),
];

class AccountsHomePage extends StatefulWidget {
  const AccountsHomePage({super.key});

  @override
  State<AccountsHomePage> createState() => _AccountsHomePageState();
}

class _AccountsHomePageState extends State<AccountsHomePage> {
  static const MethodChannel _channel =
      MethodChannel('com.example.chatgpt_accounts/profiles');

  late final Future<bool> _profilesSupported;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _profilesSupported = _checkProfileSupport();
  }

  Future<bool> _checkProfileSupport() async {
    try {
      return await _channel.invokeMethod<bool>('isMultiProfileSupported') ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> _handleBack() async {
    try {
      await _channel.invokeMethod<bool>('handleBack', {
        'profileName': _accountProfiles[_selectedIndex].profileName,
      });
    } on PlatformException {
      // Back should never close the app.
    } on MissingPluginException {
      // Back should never close the app.
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(_accountProfiles[_selectedIndex].label),
        centerTitle: true,
      ),
      body: FutureBuilder<bool>(
        future: _profilesSupported,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.data != true) {
            return const _UnsupportedProfilesMessage();
          }

          return IndexedStack(
            index: _selectedIndex,
            children: _accountProfiles
                .map(
                  (account) => _AccountWebView(
                    key: ValueKey(account.profileName),
                    profileName: account.profileName,
                  ),
                )
                .toList(growable: false),
          );
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          if (index < 0 || index >= _accountProfiles.length) {
            return;
          }
          setState(() => _selectedIndex = index);
        },
        destinations: _accountProfiles
            .map(
              (account) => NavigationDestination(
                icon: Icon(account.icon),
                selectedIcon: Icon(account.selectedIcon),
                label: account.label,
              ),
            )
            .toList(growable: false),
      ),
      ),
    );
  }
}

class _AccountWebView extends StatelessWidget {
  const _AccountWebView({
    super.key,
    required this.profileName,
  });

  final String profileName;

  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: 'chatgpt/accounts_webview',
      creationParams: <String, String>{
        'profileName': profileName,
        'initialUrl': 'https://chatgpt.com/',
      },
      creationParamsCodec: const StandardMessageCodec(),
    );
  }
}

class _UnsupportedProfilesMessage extends StatelessWidget {
  const _UnsupportedProfilesMessage();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'نسخه WebView این دستگاه از نشست‌های مستقل پشتیبانی نمی‌کند. '
          'برای جلوگیری از ورود اشتباه یا مشترک شدن حساب‌ها، صفحه‌ها باز نشدند. '
          'لطفاً Android System WebView یا Chrome را به‌روزرسانی کنید و دوباره برنامه را باز کنید.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, height: 1.8),
        ),
      ),
    );
  }
}
