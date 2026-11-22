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
      title: 'دو حساب ChatGPT',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedIndex == 0 ? 'حساب اول' : 'حساب دوم'),
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
            children: const [
              _AccountWebView(
                key: ValueKey('account-one'),
                profileName: 'chatgpt_account_one',
              ),
              _AccountWebView(
                key: ValueKey('account-two'),
                profileName: 'chatgpt_account_two',
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() => _selectedIndex = index);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'حساب اول',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_2_outlined),
            selectedIcon: Icon(Icons.person_2),
            label: 'حساب دوم',
          ),
        ],
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
          'برای جلوگیری از ورود اشتباه یا مشترک شدن دو حساب، صفحه‌ها باز نشدند. '
          'لطفاً Android System WebView یا Chrome را به‌روزرسانی کنید و دوباره برنامه را باز کنید.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, height: 1.8),
        ),
      ),
    );
  }
}
