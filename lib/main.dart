import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const TvRemoteApp());
}

class TvRemoteApp extends StatelessWidget {
  const TvRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TV Pointer & Keyboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const RoleSelectionScreen(),
    );
  }
}

class RoleSelectionScreen extends StatelessWidget {
  const RoleSelectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TV Mouse & Keyboard Remote')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.tv, size: 32),
                label: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Run as Android TV Receiver', style: TextStyle(fontSize: 18)),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TvReceiverScreen()),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.tablet_mac, size: 32),
                label: const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Text('Run as iPad / Phone Controller', style: TextStyle(fontSize: 18)),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ControllerScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 1. ANDROID TV RECEIVER (UDP Port 5005 + iPad Web App Server on Port 8080)
// ============================================================================
class TvReceiverScreen extends StatefulWidget {
  const TvReceiverScreen({super.key});

  @override
  State<TvReceiverScreen> createState() => _TvReceiverScreenState();
}

class _TvReceiverScreenState extends State<TvReceiverScreen> {
  static const platform = MethodChannel('com.example.tvremote/input');
  String ipAddress = "Detecting Wi-Fi IP...";
  RawDatagramSocket? udpSocket;
  HttpServer? webServer;

  @override
  void initState() {
    super.initState();
    _startServices();
  }

  Future<void> _startServices() async {
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          setState(() => ipAddress = addr.address);
        }
      }
    }

    // 1. Start UDP Server (Port 5005) for Native App
    udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 5005);
    udpSocket!.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final dg = udpSocket!.receive();
        if (dg != null) _handleCommand(utf8.decode(dg.data));
      }
    });

    // 2. Start HTTP/WebSocket Server (Port 8080) for iPad Safari Web App
    webServer = await HttpServer.bind(InternetAddress.anyIPv4, 8080);
    webServer!.listen((HttpRequest req) async {
      if (WebSocketTransformer.isUpgradeRequest(req)) {
        final ws = await WebSocketTransformer.upgrade(req);
        ws.listen((data) => _handleCommand(data.toString()));
      } else {
        req.response.headers.contentType = ContentType.html;
        req.response.write(_ipadWebHtml);
        await req.response.close();
      }
    });
  }

  void _handleCommand(String msg) {
    final parts = msg.split(':');
    if (parts[0] == 'M' && parts.length == 3) {
      platform.invokeMethod('moveCursor', {
        'dx': double.tryParse(parts[1]) ?? 0.0,
        'dy': double.tryParse(parts[2]) ?? 0.0,
      });
    } else if (parts[0] == 'C') {
      platform.invokeMethod('clickCursor');
    } else if (parts[0] == 'S' && parts.length == 2) {
      platform.invokeMethod('scrollCursor', {'dy': double.tryParse(parts[1]) ?? 0.0});
    } else if (parts[0] == 'K' && parts.length >= 2) {
      platform.invokeMethod('sendText', {'text': parts.sublist(1).join(':')});
    } else if (parts[0] == 'B') {
      platform.invokeMethod('pressBack');
    } else if (parts[0] == 'H') {
      platform.invokeMethod('pressHome');
    }
  }

  @override
  void dispose() {
    udpSocket?.close();
    webServer?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Android TV Receiver Active')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_tethering, size: 56, color: Colors.greenAccent),
            const SizedBox(height: 12),
            Text('TV IP: $ipAddress', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Native App Port: 5005  |  iPad Safari URL: http://$ipAddress:8080',
                style: const TextStyle(color: Colors.amberAccent, fontSize: 16)),
            const SizedBox(height: 24),
            ElevatedButton(
              autofocus: true,
              onPressed: () => platform.invokeMethod('openAccessibilitySettings'),
              child: const Padding(
                padding: EdgeInsets.all(12.0),
                child: Text('Enable "TV Mouse Service" in Accessibility Settings', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Once enabled, a mouse pointer will appear on your TV screen.',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 2. NATIVE CONTROLLER SCREEN (For iPad .ipa & Android Phone .apk)
// ============================================================================
class ControllerScreen extends StatefulWidget {
  const ControllerScreen({super.key});

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  final TextEditingController _ipController = TextEditingController(text: '192.168.1.');
  final TextEditingController _kbController = TextEditingController();
  RawDatagramSocket? _socket;

  @override
  void initState() {
    super.initState();
    RawDatagramSocket.bind(InternetAddress.anyIPv4, 0).then((s) => _socket = s);
  }

  void _send(String cmd) {
    final ip = InternetAddress.tryParse(_ipController.text.trim());
    if (ip != null && _socket != null) {
      _socket!.send(utf8.encode(cmd), ip, 5005);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ipController,
          decoration: const InputDecoration(labelText: 'Enter TV IP Address', border: InputBorder.none),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.keyboard), onPressed: () => _showKeyboard(context)),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                // Main Trackpad Area
                Expanded(
                  flex: 5,
                  child: GestureDetector(
                    onPanUpdate: (d) => _send('M:${(d.delta.dx * 1.8).toStringAsFixed(1)}:${(d.delta.dy * 1.8).toStringAsFixed(1)}'),
                    onTap: () => _send('C:left'),
                    child: Container(
                      margin: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blueAccent, width: 2),
                      ),
                      child: const Center(
                        child: Text('TRACKPAD\nDrag to Move Pointer • Tap to Click',
                            textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
                      ),
                    ),
                  ),
                ),
                // Dedicated Scroll Strip on Right Edge
                Expanded(
                  flex: 1,
                  child: GestureDetector(
                    onVerticalDragUpdate: (d) => _send('S:${(d.delta.dy * 2.5).toStringAsFixed(1)}'),
                    child: Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 12, right: 12),
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.tealAccent),
                      ),
                      child: const Center(
                        child: RotatedBox(
                          quarterTurns: 3,
                          child: Text('SCROLL BAR', style: TextStyle(color: Colors.white54)),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(icon: const Icon(Icons.arrow_back), label: const Text('Back'), onPressed: () => _send('B')),
                ElevatedButton.icon(icon: const Icon(Icons.home), label: const Text('Home'), onPressed: () => _send('H')),
                ElevatedButton.icon(icon: const Icon(Icons.mouse), label: const Text('Click'), onPressed: () => _send('C:left')),
              ],
            ),
          )
        ],
      ),
    );
  }

  void _showKeyboard(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom + 16, left: 16, right: 16, top: 16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _kbController,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Type text to send to TV focused box...'),
                onSubmitted: (v) {
                  _send('K:$v');
                  _kbController.clear();
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: () {
                _send('K:${_kbController.text}');
                _kbController.clear();
              },
            )
          ],
        ),
      ),
    );
  }
}

// Built-in HTML5 Web Remote for iPad Safari (Zero-Sideload Option)
const String _ipadWebHtml = '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <title>TV Touchpad</title>
  <style>
    body { margin:0; background:#121212; color:#fff; font-family:sans-serif; display:flex; flex-direction:column; height:100vh; overflow:hidden; user-select:none; -webkit-user-select:none; }
    #pad { flex:1; margin:12px; background:#1e1e1e; border:2px solid #448aff; border-radius:16px; display:flex; align-items:center; justify-content:center; color:#777; font-size:20px; touch-action:none; }
    .bar { display:flex; gap:10px; padding:0 12px 20px 12px; }
    button, input { padding:14px; border-radius:10px; border:none; background:#2c2c2c; color:#fff; font-size:16px; }
    input { flex:1; }
  </style>
</head>
<body>
  <div id="pad">iPad Trackpad (Drag to Move • Tap to Click)</div>
  <div class="bar">
    <button onclick="ws.send('B')">Back</button>
    <button onclick="ws.send('H')">Home</button>
    <input id="kb" placeholder="Type text for TV..." onkeydown="if(event.key==='Enter'){ws.send('K:'+this.value);this.value='';}">
    <button onclick="let i=document.getElementById('kb');ws.send('K:'+i.value);i.value='';">Send</button>
  </div>
  <script>
    const ws = new WebSocket('ws://' + location.host);
    const pad = document.getElementById('pad');
    let lx = 0, ly = 0, moved = false;
    pad.addEventListener('touchstart', e => { lx = e.touches[0].clientX; ly = e.touches[0].clientY; moved = false; });
    pad.addEventListener('touchmove', e => {
      e.preventDefault(); moved = true;
      let dx = (e.touches[0].clientX - lx) * 1.8;
      let dy = (e.touches[0].clientY - ly) * 1.8;
      lx = e.touches[0].clientX; ly = e.touches[0].clientY;
      ws.send('M:' + dx.toFixed(1) + ':' + dy.toFixed(1));
    }, {passive:false});
    pad.addEventListener('touchend', e => { if(!moved) ws.send('C:left'); });
  </script>
</body>
</html>
''';
