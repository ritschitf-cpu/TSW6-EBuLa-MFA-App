import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  runApp(const TswApp());
}
class TswApp extends StatelessWidget {
  const TswApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(debugShowCheckedModeBanner:false, theme:ThemeData.dark(useMaterial3:true), home:const Dashboard());
}
class Dashboard extends StatefulWidget {
  const Dashboard({super.key});
  State<Dashboard> createState()=>_DashboardState();
}
class _DashboardState extends State<Dashboard> {
  WebSocketChannel? channel;
  StreamSubscription? sub;
  String host='192.168.0.100', port='8765';
  bool connected=false;
  Map<String,dynamic> data={};
  dynamic val(String key,[dynamic fallback='--'])=>data[key]??fallback;
  @override
  void initState(){super.initState(); _load();}
  Future<void> _load() async {
    final p=await SharedPreferences.getInstance();
    if(!mounted)return;
    setState((){host=p.getString('host')??host;port=p.getString('port')??port;});
  }
  void connect() {
    sub?.cancel(); channel?.sink.close();
    try {
      final c=WebSocketChannel.connect(Uri.parse('ws://$host:$port'));
      channel=c;
      sub=c.stream.listen((raw){
        try{final x=jsonDecode(raw.toString()); if(x is Map)setState(()=>data=Map<String,dynamic>.from(x));}catch(_){}
      },onDone:()=>setState(()=>connected=false),onError:(_)=>setState(()=>connected=false));
      setState(()=>connected=true);
      SharedPreferences.getInstance().then((p){p.setString('host',host);p.setString('port',port);});
    } catch(_){setState(()=>connected=false);}
  }
  Widget card(String a,String b)=>Card(child:Padding(padding:const EdgeInsets.all(10),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(a),Text(b,style:const TextStyle(fontWeight:FontWeight.bold))])));
  Widget settings(){
    final h=TextEditingController(text:host), p=TextEditingController(text:port);
    return AlertDialog(title:const Text('TSW6 Bridge'),content:Column(mainAxisSize:MainAxisSize.min,children:[TextField(controller:h,decoration:const InputDecoration(labelText:'PC-IP')),TextField(controller:p,decoration:const InputDecoration(labelText:'Port'))]),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Abbrechen')),FilledButton(onPressed:(){host=h.text.trim();port=p.text.trim();Navigator.pop(context);connect();},child:const Text('Verbinden'))]);
  }
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:Colors.black,
    body:SafeArea(child:Row(children:[
      Expanded(flex:5,child:Center(child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
        Text('GESCHWINDIGKEIT',style:TextStyle(color:Colors.grey.shade400,fontSize:16)),
        Text('${val('speed',val('speed_kmh',0))}',style:const TextStyle(fontSize:112,fontWeight:FontWeight.w700)),
        Text('km/h',style:TextStyle(color:Colors.grey.shade400,fontSize:18))
      ]))),
      Expanded(flex:2,child:Padding(padding:const EdgeInsets.all(16),child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
        card('Vmax','${val('speed_limit',val('vmax'))} km/h'),card('PZB','${val('pzb')}'),card('LZB','${val('lzb')}'),card('SIFA','${val('sifa')}'),card('Türen','${val('doors')}'),card('Fahrzeug','${val('vehicle_profile')}')
      ])))
    ])),
    floatingActionButton:FloatingActionButton.extended(onPressed:()=>showDialog(context:context,builder:(_)=>settings()),label:Text(connected?'Verbunden':'Verbinden'),icon:Icon(connected?Icons.link:Icons.link_off))
  );
  void dispose(){sub?.cancel();channel?.sink.close();super.dispose();}
}
