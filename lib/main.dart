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
      appBar: AppBar(title: const Text('Select Device Mode')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.tv, size: 32),
              label: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Start as Android TV Receiver', style: TextStyle(fontSize: 18)),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TvReceiverScreen()),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.touch_app, size: 32),
              label: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text('Start as iPad / Phone Controller', style: TextStyle(fontSize: 18)),
              ),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ControllerScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 1. TV RECEIVER SCREEN (Runs on Android TV)
// ============================================================================
class TvReceiverScreen extends StatefulWidget {
  const TvReceiverScreen({super.key});

  @override
  State<TvReceiverScreen> createState() => _TvReceiverScreenState();
}

class _TvReceiverScreenState extends State<TvReceiverScreen> {
  static const platform = MethodChannel('com.example.tvremote/input');
  String ipAddress = "Detecting IP...";
  RawDatagramSocket? udpSocket;

  @override
  void initState() {
    super.initState();
    _startReceiver();
  }

  Future<void> _startReceiver() async {
    // Get Local Wi-Fi IP
    for (var interface in await NetworkInterface.list()) {
      for (var addr in interface.addresses) {
        if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
          setState(() => ipAddress = addr.address);
        }
      }
    }

    // Bind UDP Port 5005 for low-latency trackpad packets
    udpSocket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 5005);
    udpSocket!.listen((RawSocketEvent event) {
      if (event == RawSocketEvent.read) {
        final dg = udpSocket!.receive();
        if (dg != null) {
          final msg = utf8.decode(dg.data);
          _handleCommand(msg);
        }
      }
    });
  }

  void _handleCommand(String msg) {
    // Format: "M:dx:dy" (Move), "C:left" (Click), "K:text" (Keyboard)
    final parts = msg.split(':');
    if (parts[0] == 'M' && parts.length == 3) {
      platform.invokeMethod('moveCursor', {
        'dx': double.tryParse(parts[1]) ?? 0.0,
        'dy': double.tryParse(parts[2]) ?? 0.0,
      });
    } else if (parts[0] == 'C') {
      platform.invokeMethod('clickCursor');
    } else if (parts[0] == 'K' && parts.length >= 2) {
      platform.invokeMethod('sendText', {'text': parts.sublist(1).join(':')});
    } else if (parts[0] == 'B') {
      platform.invokeMethod('pressBack');
    }
  }

  @override
  void dispose() {
    udpSocket?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('TV Receiver Active')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_tethering, size: 64, color: Colors.greenAccent),
            const SizedBox(height: 16),
            Text('TV IP Address: $ipAddress', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Listening on UDP Port 5005', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => platform.invokeMethod('openAccessibilitySettings'),
              child: const Text('1. Enable Accessibility Service (For Clicks)'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => platform.invokeMethod('openOverlaySettings'),
              child: const Text('2. Enable Display Over Other Apps (For Pointer)'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 2. CONTROLLER SCREEN (Runs on iPad / Android Phone)
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
  double sensitivity = 1.8;

  @override
  void initState() {
    super.initState();
    RawDatagramSocket.bind(InternetAddress.anyIPv4, 0).then((s) => _socket = s);
  }

  void _sendUdp(String payload) {
    final ip = InternetAddress.tryParse(_ipController.text.trim());
    if (ip != null && _socket != null) {
      _socket!.send(utf8.encode(payload), ip, 5005);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ipController,
          decoration: const InputDecoration(labelText: 'TV IP Address', border: InputBorder.none),
          keyboardType: TextInputType.number,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.keyboard),
            onPressed: () => _showKeyboardModal(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Trackpad Surface
          Expanded(
            child: GestureDetector(
              onPanUpdate: (details) {
                final dx = (details.delta.dx * sensitivity).toStringAsFixed(1);
                final dy = (details.delta.dy * sensitivity).toStringAsFixed(1);
                _sendUdp('M:$dx:$dy');
              },
              onTap: () => _sendUdp('C:left'),
              child: Container(
                margin: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.5), width: 2),
                ),
                child: const Center(
                  child: Text(
                    'Trackpad Area\nDrag to move pointer • Tap to click',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54, fontSize: 18),
                  ),
                ),
              ),
            ),
          ),
          // Bottom Hardware Control Bar
          Padding(
            padding: const EdgeInsets.only(bottom: 24, left: 16, right: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Back'),
                  onPressed: () => _sendUdp('B:back'),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.mouse),
                  label: const Text('Left Click'),
                  onPressed: () => _sendUdp('C:left'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showKeyboardModal(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          left: 16, right: 16, top: 16,
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _kbController,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Type text to send to TV...'),
                onSubmitted: (val) {
                  _sendUdp('K:$val');
                  _kbController.clear();
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: () {
                _sendUdp('K:${_kbController.text}');
                _kbController.clear();
              },
            )
          ],
        ),
      ),
    );
  }
}
