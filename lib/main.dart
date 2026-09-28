import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
  runApp(const EbulaApp());
}

class RowData {
  final double km;
  final String text;
  final String? time;
  final String? symbol;
  const RowData(this.km, this.text, {this.time, this.symbol});
  factory RowData.fromJson(Map<String, dynamic> j) => RowData(
    (j['km'] as num).toDouble(), j['text'] as String,
    time: j['time'] as String?, symbol: j['symbol'] as String?,
  );
}

class Schedule {
  final String train, origin, destination, date, nextStop;
  final double maxSpeed;
  final List<RowData> rows;
  const Schedule({required this.train, required this.origin, required this.destination,
    required this.date, required this.nextStop, required this.maxSpeed, required this.rows});
  factory Schedule.fromJson(Map<String, dynamic> j) => Schedule(
    train: j['train'], origin: j['origin'], destination: j['destination'],
    date: j['date'], nextStop: j['nextStop'], maxSpeed: (j['maxSpeed'] as num).toDouble(),
    rows: (j['rows'] as List).map((e) => RowData.fromJson(e)).toList(),
  );
}

class Telemetry {
  final bool connected;
  final double speedKmh;
  final DateTime? simulationTime;
  const Telemetry({this.connected = false, this.speedKmh = 0, this.simulationTime});
  factory Telemetry.fromJson(Map<String, dynamic> j) => Telemetry(
    connected: j['connected'] == true,
    speedKmh: (j['speedKmh'] ?? 0).toDouble(),
    simulationTime: j['simulationTime'] == null ? null : DateTime.tryParse(j['simulationTime']),
  );
}

class EbulaApp extends StatefulWidget {
  const EbulaApp({super.key});
  @override State<EbulaApp> createState() => _EbulaAppState();
}

class _EbulaAppState extends State<EbulaApp> {
  Schedule? schedule;
  String pcHost = '192.168.178.20';
  Telemetry telemetry = const Telemetry();
  Timer? timer;
  StreamSubscription? socketSub;
  WebSocketChannel? socket;
  DateTime clock = DateTime(2020, 9, 28, 8, 4, 37);
  int page = 0, correction = 0;
  bool night = false, dark = true, paused = false, timeMode = true;
  double brightness = 1;

  @override void initState() {
    super.initState();
    _load();
    _connect();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!paused && timeMode && telemetry.simulationTime == null && mounted) {
        setState(() => clock = clock.add(const Duration(seconds: 1)));
      }
    });
    _connect();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    pcHost = prefs.getString('pcHost') ?? '192.168.178.20';
    final raw = await rootBundle.loadString('assets/schedules/ice15.json');
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      schedule = Schedule.fromJson(jsonDecode(raw));
      night = p.getBool('night') ?? false;
      dark = p.getBool('dark') ?? true;
      brightness = p.getDouble('brightness') ?? 1;
      pcHost = p.getString('pcHost') ?? pcHost;
    });
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('night', night);
    await p.setBool('dark', dark);
    await p.setDouble('brightness', brightness);
    await p.setString('pcHost', pcHost);
  }

  void _connect() {
    try {
      socketSub?.cancel();
      socket?.sink.close();
      socket = WebSocketChannel.connect(Uri.parse('ws://$pcHost:31271/ebula'));
      socketSub = socket!.stream.listen((data) {
        final j = jsonDecode(data as String);
        if (j['type'] == 'telemetry' && mounted) {
          final t = Telemetry.fromJson(j['data']);
          setState(() {
            telemetry = t;
            if (timeMode && t.simulationTime != null) clock = t.simulationTime!;
          });
        }
      }, onError: (_) {}, onDone: () {});
    } catch (_) {}
  }

  @override void dispose() {
    timer?.cancel(); socketSub?.cancel(); socket?.sink.close(); super.dispose();
  }

  String _clock() => clock.hour.toString().padLeft(2, '0') + ':' +
      clock.minute.toString().padLeft(2, '0') + ':' +
      clock.second.toString().padLeft(2, '0');

  void _adjust(int h, int m) => setState(() => clock = DateTime(
    clock.year, clock.month, clock.day, clock.hour + h, clock.minute + m, clock.second));

  @override Widget build(BuildContext context) {
    final bg = dark ? Colors.black : const Color(0xffeeeeee);
    final fg = dark ? Colors.white : Colors.black;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: false, fontFamily: 'monospace'),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(child: Center(child: LayoutBuilder(builder: (context, c) {
          final scale = (c.maxWidth / 1024).clamp(.72, 1.8).toDouble();
          return Transform.scale(scale: scale, child: SizedBox(
            width: 1024, height: 600,
            child: Column(children: [
              _top(),
              Expanded(child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                child: Container(
                  decoration: BoxDecoration(color: bg, border: Border.all(color: Colors.white, width: 2)),
                  child: Opacity(opacity: brightness, child: _screen(fg)),
                ),
              )),
              _bottom(),
            ]),
          ));
        }))),
      ),
    );
  }

  Widget _top() {
    final labels = ['aus', 'S', 'I', 'St', '-5s', '+5s', '✱', '◐', 'UD'];
    return SizedBox(height: 86, child: Row(children: [
      for (int i = 0; i < labels.length; i++) Expanded(
        flex: i == 3 ? 2 : 1,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: _key(labels[i], night, () {
            if (labels[i] == 'S') setState(() => paused = !paused);
            if (labels[i] == '-5s') setState(() => correction -= 5);
            if (labels[i] == '+5s') setState(() => correction += 5);
            if (labels[i] == '✱') setState(() => night = !night);
            if (labels[i] == '◐') setState(() => dark = !dark);
            if (labels[i] == 'UD') _page(1);
            _save();
          }),
        ),
      ),
    ]));
  }

  Widget _bottom() {
    final labels = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
    return SizedBox(height: 78, child: Row(children: [
      for (final l in labels) Expanded(child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
        child: _key(l, night, () {
          if (l == '1') _info();
          if (l == '2') setState(() => timeMode = !timeMode);
          if (l == '3') setState(() => page = 0);
          if (l == '4') _adjust(1, 0);
          if (l == '5') _adjust(-1, 0);
          if (l == '6') _adjust(0, 1);
          if (l == '7') _adjust(0, -1);
          if (l == '8') setState(() => brightness = (brightness + .1).clamp(.4, 1.0).toDouble());
          if (l == '9') setState(() => brightness = (brightness - .1).clamp(.4, 1.0).toDouble());
          if (l == '0') _settings();
          _save();
        }),
      )),
    ]));
  }

  void _page(int delta) => setState(() => page = (page + delta).clamp(0, 9999));

  Widget _key(String label, bool red, VoidCallback tap) => GestureDetector(
    onTap: tap,
    child: DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: red ? const Color(0xffff4b43) : const Color(0xffffa14a), width: 3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(child: Text(label, textAlign: TextAlign.center,
        style: TextStyle(color: red ? const Color(0xffff4b43) : const Color(0xffffa14a),
          fontSize: 20, fontWeight: FontWeight.w800))),
    ),
  );

  Widget _screen(Color fg) {
    final s = schedule;
    if (s == null) return Center(child: Text('EBuLa', style: TextStyle(color: fg, fontSize: 30)));
    final rows = s.rows.skip(page).take(10).toList();
    return Column(children: [
      SizedBox(height: 70, child: Row(children: [
        _head(s.train, 1, fg), _head(s.origin, 3, fg), _head(s.date, 2, fg), _head(_clock(), 1.4, fg),
      ])),
      Container(height: 2, color: fg),
      SizedBox(height: 36, child: Row(children: [
        Expanded(flex: 22, child: Text('ab km 2,5: ' + s.maxSpeed.toInt().toString() + ' km/h',
          style: TextStyle(color: fg, fontSize: 18, fontWeight: FontWeight.bold))),
        Expanded(flex: 28, child: Text('Nächster Halt: ' + s.nextStop,
          style: TextStyle(color: fg, fontSize: 18, fontWeight: FontWeight.bold))),
      ])),
      Expanded(child: Row(children: [
        SizedBox(width: 330, child: CustomPaint(
          painter: _ProfilePainter(fg),
          child: Center(child: Text(telemetry.connected ? telemetry.speedKmh.toStringAsFixed(0) : '160',
            style: const TextStyle(color: Colors.blue, fontSize: 18, fontWeight: FontWeight.bold))),
        )),
        Expanded(child: ListView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rows.length,
          itemBuilder: (c, i) {
            final r = rows[i];
            return SizedBox(height: 47, child: Row(children: [
              SizedBox(width: 75, child: Text(r.km.toStringAsFixed(1), style: TextStyle(color: fg, fontSize: 17))),
              Expanded(child: Row(children: [
                if (r.symbol != null) Container(
                  width: 48, height: 34, alignment: Alignment.center,
                  decoration: BoxDecoration(border: Border.all(color: fg)),
                  child: Text(r.symbol!, style: TextStyle(color: fg, fontSize: 16)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(r.text, style: TextStyle(color: fg, fontSize: 17))),
              ])),
              SizedBox(width: 90, child: Text(r.time ?? '', style: TextStyle(color: fg, fontSize: 17))),
            ]));
          },
        )),
      ])),
      Container(height: 46, decoration: BoxDecoration(border: Border(top: BorderSide(color: fg))),
        child: Row(children: [
          _status('Zeit', fg), _status('RW /r', fg), _status('600 A', fg), _status('GSM-R', fg),
          _status((correction >= 0 ? '+' : '') + correction.toString() + ' s', fg),
          _status('ESF', fg), _status('+ 0 kWh', fg), _status('- 0 kWh', fg),
        ])),
    ]);
  }

  Widget _head(String text, double flex, Color fg) => Expanded(
    flex: (flex * 10).round(), child: Center(child: Text(text, textAlign: TextAlign.center,
      style: TextStyle(color: fg, fontSize: 20, fontWeight: FontWeight.w700))));
  Widget _status(String text, Color fg) => Expanded(
    child: Center(child: Text(text, style: TextStyle(color: fg, fontSize: 15, fontWeight: FontWeight.bold))));

  void _settings() {
    final c = TextEditingController(text: pcHost);
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: Colors.black,
      title: const Text('TSW6 Verbindung', style: TextStyle(color: Colors.white)),
      content: TextField(controller: c, style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(labelText: 'PC-IP / Hostname', labelStyle: TextStyle(color: Colors.orange))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('C')),
        TextButton(onPressed: () {
          setState(() => pcHost = c.text.trim());
          _save();
          _connect();
          Navigator.pop(context);
        }, child: const Text('VERBINDEN')),
      ],
    ));
  }

  void _info() {
    showDialog(context: context, builder: (_) => AlertDialog(
      backgroundColor: Colors.black,
      title: const Text('Zug / FSD', style: TextStyle(color: Colors.white)),
      content: Text(
        'Zug: ' + (schedule?.train ?? '-') +
        '\nStrecke: ' + (schedule?.origin ?? '-') + ' → ' + (schedule?.destination ?? '-') +
        '\nVmax: ' + (schedule?.maxSpeed.toInt().toString() ?? '0') +
        ' km/h\nBridge: ' + (telemetry.connected ? 'verbunden' : 'Demo / lokal'),
        style: const TextStyle(color: Colors.white)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('C'))],
    ));
  }
}

class _ProfilePainter extends CustomPainter {
  final Color fg;
  _ProfilePainter(this.fg);
  @override void paint(Canvas c, Size s) {
    final p = Paint()..color = fg..strokeWidth = 2..style = PaintingStyle.stroke;
    final x = s.width * .52;
    c.drawLine(Offset(x, 0), Offset(x, s.height), p);
    c.drawLine(Offset(x - 60, 0), Offset(x - 60, s.height), p);
    c.drawLine(Offset(x + 60, 0), Offset(x + 60, s.height), p);
    final d = Path()..moveTo(x, s.height * .45 - 14)..lineTo(x + 14, s.height * .45)
      ..lineTo(x, s.height * .45 + 14)..lineTo(x - 14, s.height * .45)..close();
    c.drawPath(d, Paint()..color = fg);
    c.drawRect(Rect.fromLTWH(x - 26, s.height - 50, 52, 32), Paint()..color = Colors.blue);
  }
  @override bool shouldRepaint(covariant _ProfilePainter old) => old.fg != fg;
}
