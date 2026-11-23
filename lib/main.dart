import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() { WidgetsFlutterBinding.ensureInitialized(); runApp(const ChatGPTAccountsApp()); }
class ChatGPTAccountsApp extends StatelessWidget {
 const ChatGPTAccountsApp({super.key});
 @override Widget build(BuildContext context) => MaterialApp(debugShowCheckedModeBanner:false,title:'accounts',theme:ThemeData(colorScheme:ColorScheme.fromSeed(seedColor:const Color(0xFF10A37F),brightness:Brightness.light),useMaterial3:true),home:const AccountsHomePage());
}
class _AccountProfile { const _AccountProfile({required this.profileName,required this.defaultLabel}); final String profileName; final String defaultLabel; }
const _accountProfiles=[
 _AccountProfile(profileName:'chatgpt_account_one',defaultLabel:'حساب ۱'),
 _AccountProfile(profileName:'chatgpt_account_two',defaultLabel:'حساب ۲'),
 _AccountProfile(profileName:'chatgpt_account_three',defaultLabel:'حساب ۳'),
 _AccountProfile(profileName:'chatgpt_account_four',defaultLabel:'حساب ۴'),
];
class AccountsHomePage extends StatefulWidget { const AccountsHomePage({super.key}); @override State<AccountsHomePage> createState()=>_AccountsHomePageState(); }
class _AccountsHomePageState extends State<AccountsHomePage>{
 static const _channel=MethodChannel('com.example.chatgpt_accounts/profiles');
 late final Future<bool> _profilesSupported; int _selectedIndex=0;
 List<String> _labels=_accountProfiles.map((a)=>a.defaultLabel).toList();
 @override void initState(){super.initState();_profilesSupported=_checkProfileSupport();_loadLabels();}
 Future<void> _loadLabels()async{try{final saved=await _channel.invokeMethod<List<dynamic>>('getAccountLabels');if(saved!=null&&saved.length==4){final names=saved.map((e)=>e.toString().trim()).toList();if(names.every((e)=>e.isNotEmpty)&&mounted)setState(()=>_labels=names);}}catch(_){}}
 Future<void> _saveLabels()async{try{await _channel.invokeMethod<void>('saveAccountLabels',{'labels':_labels});}catch(_){}}
 Future<void> _rename(int i)async{final ctl=TextEditingController(text:_labels[i]);final name=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:const Text('تغییر نام حساب'),content:TextField(controller:ctl,autofocus:true,maxLength:30,textDirection:TextDirection.rtl,decoration:const InputDecoration(labelText:'نام حساب'),onSubmitted:(v){if(v.trim().isNotEmpty)Navigator.pop(ctx,v.trim());}),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('لغو')),FilledButton(onPressed:(){if(ctl.text.trim().isNotEmpty)Navigator.pop(ctx,ctl.text.trim());},child:const Text('ذخیره'))]));ctl.dispose();if(name==null||name.trim().isEmpty||!mounted)return;setState(()=>_labels[i]=name.trim());await _saveLabels();}
 Future<bool> _checkProfileSupport()async{try{return await _channel.invokeMethod<bool>('isMultiProfileSupported')??false;}on PlatformException{return false;}on MissingPluginException{return false;}}
 Future<void> _handleBack()async{try{await _channel.invokeMethod<bool>('handleBack',{'profileName':_accountProfiles[_selectedIndex].profileName});}on PlatformException{}on MissingPluginException{}}
 @override Widget build(BuildContext context)=>PopScope(canPop:false,onPopInvoked:(didPop){if(!didPop)_handleBack();},child:Scaffold(appBar:AppBar(title:Text(_labels[_selectedIndex]),centerTitle:true),body:FutureBuilder<bool>(future:_profilesSupported,builder:(context,s){if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());if(s.data!=true)return const _UnsupportedProfilesMessage();return IndexedStack(index:_selectedIndex,children:_accountProfiles.map((a)=>_AccountWebView(key:ValueKey(a.profileName),profileName:a.profileName)).toList(growable:false);}),bottomNavigationBar:NavigationBar(selectedIndex:_selectedIndex,onDestinationSelected:(i){if(i>=0&&i<4)setState(()=>_selectedIndex=i;);},destinations:List.generate(4,(i)=>NavigationDestination(icon:_HoldRenameIcon(onRename:()=>_rename(i)),selectedIcon:_HoldRenameIcon(onRename:()=>_rename(i)),label:_labels[i])))));
}
class _HoldRenameIcon extends StatefulWidget{const _HoldRenameIcon({required this.onRename});final VoidCallback onRename;@override State<_HoldRenameIcon> createState()=>_HoldRenameIconState();}
class _HoldRenameIconState extends State<_HoldRenameIcon>{Timer? _timer;void _down(PointerDownEvent e){_timer?.cancel();_timer=Timer(const Duration(seconds:3),widget.onRename);}void _cancel(PointerEvent e){_timer?.cancel();_timer=null;}@override void dispose(){_timer?.cancel();super.dispose();}@override Widget build(BuildContext context)=>Listener(onPointerDown:_down,onPointerUp:_cancel,onPointerCancel:_cancel,child:const Icon(Icons.account_circle));}
class _AccountWebView extends StatelessWidget{const _AccountWebView({super.key,required this.profileName});final String profileName;@override Widget build(BuildContext context)=>AndroidView(viewType:'chatgpt/accounts_webview',creationParams:<String,String>{'profileName':profileName,'initialUrl':'https://chatgpt.com/'},creationParamsCodec:const StandardMessageCodec());}
class _UnsupportedProfilesMessage extends StatelessWidget{const _UnsupportedProfilesMessage();@override Widget build(BuildContext context)=>const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('نسخه WebView این دستگاه از نشست‌های مستقل پشتیبانی نمی‌کند. برای جلوگیری از ورود اشتباه یا مشترک شدن حساب‌ها، صفحه‌ها باز نشدند. لطفاً Android System WebView یا Chrome را به‌روزرسانی کنید و دوباره برنامه را باز کنید.',textAlign:TextAlign.center,style:TextStyle(fontSize:16,height:1.8))));}
