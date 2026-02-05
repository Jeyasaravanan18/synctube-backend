import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  runApp(const SyncTubeApp());
}

class SyncTubeApp extends StatelessWidget {
  const SyncTubeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SyncTube Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red, brightness: Brightness.dark),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _roomController = TextEditingController();
  final TextEditingController _videoController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  
  WebSocketChannel? _channel;
  late YoutubePlayerController _controller;
  
  String? _roomId;
  String? _nickname;
  bool _isJoined = false;
  bool _isMiniPlayer = false;
  bool _isRemoteEvent = false;
  bool _isHost = false;
  List<String> _users = [];
  
  StreamSubscription? _socketSubscription;
  Timer? _syncTimer;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: true,
        mute: false,
        showVideoAnnotations: false,
        showFullscreenButton: false,
      ),
    );
  }

  void _connect(String roomId, String nickname) {
    // IMPORTANT: Change this to your public Render/Heroku URL for APK distribution
    final uri = Uri.parse('wss://synctube-server-demo.onrender.com'); 
    
    try {
      _channel = WebSocketChannel.connect(uri);
      _sendEvent({'type': 'JOIN', 'roomId': roomId, 'nickname': nickname});

      _socketSubscription = _channel!.stream.listen(
        (data) => _handleRemoteEvent(jsonDecode(data)),
        onError: (err) => _showSnackBar('Connection error. Please try again.'),
        onDone: () => _showSnackBar('Connection closed.'),
      );

      setState(() {
        _roomId = roomId;
        _nickname = nickname;
        _isJoined = true;
      });

      _startSyncHeartbeat();
    } catch (e) {
      _showSnackBar('Could not connect to server.');
    }
  }

  void _startSyncHeartbeat() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (_isHost && _isJoined && !_isRemoteEvent) {
        final pos = await _controller.currentTime;
        _syncAction('SYNC', position: pos);
      }
    });
  }

  void _sendEvent(Map<String, dynamic> event) => _channel?.sink.add(jsonEncode(event));

  void _handleRemoteEvent(Map<String, dynamic> message) async {
    if (message['nickname'] == _nickname) return;
    
    setState(() => _isRemoteEvent = true);
    
    switch (message['type']) {
      case 'JOINED':
        setState(() { 
          _isHost = message['isHost']; 
          _users = List<String>.from(message['users']); 
        });
        _showSnackBar('Joined as ${_isHost ? "Host" : "Guest"}');
        break;
      case 'USER_JOINED':
      case 'USER_LEFT':
        setState(() { _users = List<String>.from(message['users']); });
        _showSnackBar('${message['nickname']} ${message['type'] == 'USER_JOINED' ? 'joined' : 'left'}');
        break;
      case 'SYNC':
        final remotePos = (message['position'] as num).toDouble();
        final localPos = await _controller.currentTime;
        if ((remotePos - localPos).abs() > 1.5) {
          _controller.seekTo(seconds: remotePos, allowSeekAhead: true);
        }
        break;
      case 'LOAD_VIDEO': 
        _controller.loadVideoById(videoId: message['videoId']); 
        break;
      case 'PLAY': _controller.playVideo(); break;
      case 'PAUSE': _controller.pauseVideo(); break;
      case 'HOST_ASSIGNED':
        setState(() => _isHost = true);
        _showSnackBar('You are now the Host');
        _startSyncHeartbeat();
        break;
    }
    
    Future.delayed(const Duration(milliseconds: 500), () { 
      if (mounted) setState(() => _isRemoteEvent = false); 
    });
  }

  void _syncAction(String type, {double? position, String? videoId}) {
    if (_isRemoteEvent) return;
    _sendEvent({
      'type': type, 
      'position': position, 
      'videoId': videoId, 
      'roomId': _roomId, 
      'nickname': _nickname
    });
  }

  void _showSnackBar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 2))
    );
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _socketSubscription?.cancel();
    _channel?.sink.close();
    _roomController.dispose();
    _videoController.dispose();
    _nicknameController.dispose();
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _isJoined ? _buildPlayerUI() : _buildJoinUI(),
          if (_isJoined && _isMiniPlayer) _buildMiniPlayerOverlay(),
        ],
      ),
    );
  }

  Widget _buildJoinUI() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Colors.black, Color(0xFFb71c1c)], begin: Alignment.topCenter, end: Alignment.bottomCenter)
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.sync_rounded, size: 100, color: Colors.white),
          const SizedBox(height: 10),
          const Text("SyncTube Pro", style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.white)),
          const Text("SaaS Edition", style: TextStyle(color: Colors.white70, letterSpacing: 2)),
          const SizedBox(height: 50),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              children: [
                _input(_nicknameController, "Your Name", Icons.person),
                const SizedBox(height: 15),
                _input(_roomController, "Room ID", Icons.vpn_key),
                const SizedBox(height: 30),
                ElevatedButton(
                  onPressed: () {
                    if (_nicknameController.text.isNotEmpty && _roomController.text.isNotEmpty) {
                      _connect(_roomController.text, _nicknameController.text);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    minimumSize: const Size(double.infinity, 55),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
                  ),
                  child: const Text("ENTER THE ROOM", style: TextStyle(fontWeight: FontWeight.bold)),
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _input(TextEditingController controller, String hint, IconData icon) {
    return TextField(
      controller: controller, 
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: Colors.white70),
        hintText: hint, 
        filled: true, 
        fillColor: Colors.white10,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)
      )
    );
  }

  Widget _buildPlayerUI() {
    return SafeArea(
      child: Column(
        children: [
          if (!_isMiniPlayer) Hero(tag: 'player', child: YoutubePlayer(controller: _controller, aspectRatio: 16/9)),
          _buildStatusBar(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_isMiniPlayer) const SizedBox(height: 150),
                  const Text("Now Playing Controls", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _videoController,
                    decoration: InputDecoration(
                      hintText: "Enter YouTube Video ID",
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.play_circle_fill, color: Colors.red, size: 30),
                        onPressed: () {
                          final id = _videoController.text.trim();
                          if (id.isNotEmpty) {
                            _controller.loadVideoById(videoId: id);
                            _syncAction('LOAD_VIDEO', videoId: id);
                            _videoController.clear();
                          }
                        }
                      ),
                      filled: true,
                      fillColor: Colors.white10,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none)
                    ),
                  ),
                  const SizedBox(height: 30),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _btn(Icons.play_arrow, "Play", () { _controller.playVideo(); _syncAction('PLAY'); }),
                      _btn(Icons.pause, "Pause", () { _controller.pauseVideo(); _syncAction('PAUSE'); }),
                      _btn(Icons.forward_10, "Sync", () async {
                        final pos = await _controller.currentTime;
                        _syncAction('SYNC', position: pos);
                      }),
                    ],
                  ),
                  const SizedBox(height: 40),
                  Center(
                    child: TextButton.icon(
                      onPressed: () => setState(() => _isMiniPlayer = !_isMiniPlayer),
                      icon: Icon(_isMiniPlayer ? Icons.fullscreen : Icons.picture_in_picture_alt),
                      label: Text(_isMiniPlayer ? "Expand Player" : "Mini Player Mode"),
                    ),
                  )
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStatusBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: Colors.red.withOpacity(0.1),
      child: Row(
        children: [
          const Icon(Icons.radio_button_checked, color: Colors.green, size: 12),
          const SizedBox(width: 8),
          Text("Room: $_roomId", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text("Listeners: ${_users.length}", style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, String label, VoidCallback action) {
    return Column(
      children: [
        IconButton.filledTonal(onPressed: action, icon: Icon(icon), iconSize: 30),
        const SizedBox(height: 5),
        Text(label, style: const TextStyle(fontSize: 12))
      ],
    );
  }

  Widget _buildMiniPlayerOverlay() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      bottom: 30, right: 20,
      child: GestureDetector(
        onTap: () => setState(() => _isMiniPlayer = false),
        child: Hero(
          tag: 'player',
          child: Material(
            elevation: 15, borderRadius: BorderRadius.circular(20), clipBehavior: Clip.antiAlias,
            child: Container(
              width: 200, height: 112, color: Colors.black,
              child: Stack(
                children: [
                  IgnorePointer(child: YoutubePlayer(controller: _controller, aspectRatio: 16/9)),
                  Container(color: Colors.transparent),
                  const Positioned(top: 5, right: 5, child: Icon(Icons.open_in_full, size: 16, color: Colors.white70))
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
