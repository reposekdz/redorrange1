import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'dart:async';
import '../../../core/theme/app_theme.dart';
import '../../../core/services/socket_service.dart';
import '../../../shared/utils/format_utils.dart';

class CallScreen extends ConsumerStatefulWidget {
  final String callType;
  final Map<String,dynamic> extra;
  const CallScreen({super.key, required this.callType, required this.extra});
  @override ConsumerState<CallScreen> createState() => _CS();
}

class _CS extends ConsumerState<CallScreen> {
  RTCPeerConnection? _pc;
  MediaStream? _local, _remote;
  final _localR  = RTCVideoRenderer();
  final _remoteR = RTCVideoRenderer();

  String _status = 'calling';
  String _callId = '';
  int _secs = 0;
  Timer? _dur, _ctrlTimer;

  bool _muted = false, _videoOn = true, _speakerOn = true, _frontCam = true, _showCtrl = true;

  String get _uid     => widget.extra['user_id']   as String? ?? '';
  String get _uname   => widget.extra['user_name'] as String? ?? 'Unknown';
  String? get _avatar => widget.extra['avatar']    as String?;
  bool   get _incoming => widget.extra['is_incoming'] == true;
  bool   get _isVideo  => widget.callType == 'video';

  @override
  void initState() {
    super.initState();
    _localR.initialize(); _remoteR.initialize();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _setupSocket();
    _setupMedia().then((_) {
      if (_incoming) {
        _callId = widget.extra['call_id'] as String? ?? '';
        setState(() => _status = 'ringing');
        _handleOffer(widget.extra['offer']);
      } else {
        _startCall();
      }
    });
    _startCtrlTimer();
  }

  @override
  void dispose() {
    _dur?.cancel(); _ctrlTimer?.cancel();
    _local?.dispose(); _remote?.dispose();
    _pc?.close();
    _localR.dispose(); _remoteR.dispose();
    final s = ref.read(socketServiceProvider);
    s.off('call_initiated'); s.off('call_answered'); s.off('call_rejected');
    s.off('call_ended'); s.off('call_unavailable'); s.off('ice_candidate');
    s.off('remote_video_toggle'); s.off('remote_audio_toggle');
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _startCtrlTimer() {
    _ctrlTimer?.cancel();
    _ctrlTimer = Timer(const Duration(seconds: 5), () { if (mounted && _status == 'ongoing') setState(() => _showCtrl = false); });
  }

  void _tap() { setState(() => _showCtrl = true); _startCtrlTimer(); }

  Future<void> _setupMedia() async {
    try {
      _local = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': _isVideo ? {'facingMode': 'user'} : false});
      if (mounted) { _localR.srcObject = _local; setState(() {}); }
    } catch (_) {}
  }

  Future<void> _makePc() async {
    _pc = await createPeerConnection({
      'iceServers': [{'urls': ['stun:stun.l.google.com:19302', 'stun:stun1.l.google.com:19302']}],
      'sdpSemantics': 'unified-plan',
    });
    _local?.getTracks().forEach((t) => _pc!.addTrack(t, _local!));
    _pc!.onTrack = (e) { if (e.streams.isNotEmpty && mounted) setState(() { _remote = e.streams[0]; _remoteR.srcObject = _remote; }); };
    _pc!.onIceCandidate = (c) {
      if (c.candidate != null) ref.read(socketServiceProvider).sendIceCandidate(targetUserId: _uid, candidate: {'candidate': c.candidate, 'sdpMid': c.sdpMid, 'sdpMLineIndex': c.sdpMLineIndex}, callId: _callId);
    };
    _pc!.onIceConnectionState = (s) {
      if (s == RTCIceConnectionState.RTCIceConnectionStateConnected && mounted) { setState(() => _status = 'ongoing'); _startDur(); }
      else if (s == RTCIceConnectionState.RTCIceConnectionStateFailed && mounted) _hangUp();
    };
  }

  Future<void> _startCall() async {
    await _makePc();
    final o = await _pc!.createOffer();
    await _pc!.setLocalDescription(o);
    ref.read(socketServiceProvider).initiateCall(calleeId: _uid, callType: _isVideo ? 'video' : 'audio', offer: {'sdp': o.sdp, 'type': o.type});
  }

  Future<void> _handleOffer(dynamic offer) async {
    await _makePc();
    if (offer != null) await _pc!.setRemoteDescription(RTCSessionDescription(offer['sdp'], offer['type']));
  }

  Future<void> _answerCall() async {
    setState(() => _status = 'connecting');
    final a = await _pc!.createAnswer();
    await _pc!.setLocalDescription(a);
    ref.read(socketServiceProvider).answerCall(callId: _callId, callerId: _uid, answer: {'sdp': a.sdp, 'type': a.type});
  }

  void _setupSocket() {
    final s = ref.read(socketServiceProvider);
    s.on('call_initiated', (d) { if (d is Map && mounted) setState(() => _callId = d['call_id'] ?? ''); });
    s.on('call_answered', (d) async {
      if (d is! Map) return;
      final ans = d['answer'];
      if (ans != null) await _pc?.setRemoteDescription(RTCSessionDescription(ans['sdp'], ans['type']));
      if (mounted) { setState(() => _status = 'ongoing'); _startDur(); }
    });
    s.on('call_rejected', (d) { if (mounted) { setState(() => _status = 'rejected'); _autoClose(); } });
    s.on('call_ended',    (d) { if (mounted) { setState(() { _status = 'ended'; }); _dur?.cancel(); _autoClose(); } });
    s.on('call_unavailable', (_) { if (mounted) { setState(() => _status = 'unavailable'); _autoClose(); } });
    s.on('ice_candidate', (d) async {
      if (d is Map && d['from_user_id'] == _uid) {
        try {
          final c = d['candidate'];
          if (c != null) await _pc?.addCandidate(RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']));
        } catch (_) {}
      }
    });
  }

  void _startDur() { _dur = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _secs++); }); }
  void _autoClose() { Future.delayed(const Duration(seconds: 3), () { if (mounted) context.pop(); }); }

  void _hangUp() {
    if (_callId.isNotEmpty) ref.read(socketServiceProvider).endCall(callId: _callId, otherUserId: _uid);
    _dur?.cancel();
    if (mounted) context.pop();
  }

  void _reject() {
    ref.read(socketServiceProvider).rejectCall(callId: _callId, callerId: _uid);
    if (mounted) context.pop();
  }

  void _toggleMute()  { setState(() => _muted = !_muted); _local?.getAudioTracks().forEach((t) => t.enabled = !_muted); }
  void _toggleVideo() { setState(() => _videoOn = !_videoOn); _local?.getVideoTracks().forEach((t) => t.enabled = _videoOn); }
  Future<void> _flipCam() async { setState(() => _frontCam = !_frontCam); for (final t in _local?.getVideoTracks() ?? []) await Helper.switchCamera(t); }
  void _toggleSpeaker() { setState(() => _speakerOn = !_speakerOn); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: GestureDetector(onTap: _tap, child: Stack(children: [
      // Remote video
      Positioned.fill(child: _remote != null && _isVideo
        ? RTCVideoView(_remoteR, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
        : Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0D1117), Color(0xFF1A1A2E)])))),

      // Avatar for audio / no remote video
      if (!_isVideo || _remote == null)
        Positioned.fill(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          _PulseAvatar(url: _avatar, name: _uname, pulsing: _status != 'ongoing'),
          const SizedBox(height: 20),
          Text(_uname, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 28)),
          const SizedBox(height: 8),
          _CallStatus(status: _status, secs: _secs),
        ])),

      // Local PiP
      if (_isVideo && _local != null)
        Positioned(top: 88, right: 16, child: Container(width: 100, height: 145, decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white24)), child: ClipRRect(borderRadius: BorderRadius.circular(13), child: RTCVideoView(_localR, mirror: _frontCam, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)))),

      // Video overlay name
      if (_isVideo && _remote != null)
        Positioned(top: 88, left: 16, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_uname, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16, shadows: [Shadow(blurRadius: 8)])),
          _CallStatus(status: _status, secs: _secs),
        ])),

      // Top bar
      AnimatedOpacity(opacity: _showCtrl ? 1.0 : 0.0, duration: const Duration(milliseconds: 250),
        child: SafeArea(child: Row(children: [
          IconButton(icon: const Icon(Icons.arrow_back_rounded, color: Colors.white), onPressed: () => context.pop()),
          const Spacer(),
          if (_status == 'ongoing') IconButton(icon: const Icon(Icons.person_add_rounded, color: Colors.white), onPressed: () {}),
        ]))),

      // Bottom controls
      AnimatedOpacity(opacity: _showCtrl ? 1.0 : 0.0, duration: const Duration(milliseconds: 250),
        child: Positioned(bottom: 0, left: 0, right: 0, child: SafeArea(top: false,
          child: _incoming && _status == 'ringing'
            ? _IncomingRow(onAccept: _answerCall, onReject: _reject, isVideo: _isVideo)
            : _OngoingRow(muted: _muted, videoOn: _videoOn, speakerOn: _speakerOn, isVideo: _isVideo, frontCam: _frontCam, onMute: _toggleMute, onVideo: _toggleVideo, onFlip: _flipCam, onSpeaker: _toggleSpeaker, onHangUp: _hangUp)))),

      // End/Reject overlay
      if (['ended','rejected','unavailable','missed'].contains(_status))
        Positioned.fill(child: Container(color: Colors.black.withOpacity(0.7), child: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.call_end_rounded, color: Colors.red, size: 64),
          const SizedBox(height: 16),
          Text(_endLabel(), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 22)),
          if (_status == 'ended') Padding(padding: const EdgeInsets.only(top: 4), child: Text(FormatUtils.dur(_secs), style: const TextStyle(color: Colors.white60))),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: () => context.pop(), child: const Text('Close')),
        ])))),
    ])),
  );

  String _endLabel() { switch(_status) { case 'rejected': return 'Call Declined'; case 'unavailable': return 'Not Available'; case 'missed': return 'Call Missed'; default: return 'Call Ended'; } }
}

class _CallStatus extends StatelessWidget {
  final String status; final int secs;
  const _CallStatus({required this.status, required this.secs});
  @override Widget build(BuildContext _) {
    final text = status == 'ongoing' ? FormatUtils.dur(secs) : status == 'calling' ? 'Calling...' : status == 'ringing' ? 'Ringing...' : status == 'connecting' ? 'Connecting...' : status;
    return Text(text, style: TextStyle(color: status == 'ongoing' ? const Color(0xFF4CAF50) : Colors.white60, fontSize: 14, fontWeight: FontWeight.w500));
  }
}

class _PulseAvatar extends StatefulWidget {
  final String? url; final String name; final bool pulsing;
  const _PulseAvatar({this.url, required this.name, required this.pulsing});
  @override State<_PulseAvatar> createState() => _PAState();
}
class _PAState extends State<_PulseAvatar> with SingleTickerProviderStateMixin {
  late AnimationController _c; late Animation<double> _s;
  @override void initState() { super.initState(); _c = AnimationController(vsync: this, duration: const Duration(seconds: 2)); if (widget.pulsing) _c.repeat(reverse: true); _s = Tween(begin: 1.0, end: 1.08).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)); }
  @override void didUpdateWidget(_PulseAvatar old) { super.didUpdateWidget(old); if (widget.pulsing && !_c.isAnimating) _c.repeat(reverse: true); else if (!widget.pulsing) _c.stop(); }
  @override void dispose() { _c.dispose(); super.dispose(); }
  @override Widget build(BuildContext _) => ScaleTransition(scale: _s, child: Stack(alignment: Alignment.center, children: [
    ...List.generate(3, (i) => Container(width: 108.0+i*22, height: 108.0+i*22, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.055-i*0.015)))),
    Container(width: 108, height: 108, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white30, width: 2)),
      child: ClipOval(child: widget.url != null ? Image.network(widget.url!, fit: BoxFit.cover, errorBuilder: (_,__,___) => Container(color: AppTheme.orange, child: const Icon(Icons.person_rounded, color: Colors.white, size: 52))) : Container(color: AppTheme.orange, child: const Icon(Icons.person_rounded, color: Colors.white, size: 52)))),
  ]));
}

class _IncomingRow extends StatelessWidget {
  final VoidCallback onAccept, onReject; final bool isVideo;
  const _IncomingRow({required this.onAccept, required this.onReject, required this.isVideo});
  @override Widget build(BuildContext _) => Padding(padding: const EdgeInsets.fromLTRB(40, 16, 40, 52), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
    _CB(Icons.call_end_rounded, 'Decline', Colors.red, onReject),
    _CB(isVideo ? Icons.videocam_rounded : Icons.call_rounded, 'Accept', Colors.green, onAccept),
  ]));
}
class _CB extends StatelessWidget {
  final IconData i; final String l; final Color c; final VoidCallback t;
  const _CB(this.i, this.l, this.c, this.t);
  @override Widget build(BuildContext _) => GestureDetector(onTap: t, child: Column(children: [
    Container(width: 72, height: 72, decoration: BoxDecoration(color: c, shape: BoxShape.circle, boxShadow: [BoxShadow(color: c.withOpacity(0.45), blurRadius: 16, spreadRadius: 2)]), child: Icon(i, color: Colors.white, size: 30)),
    const SizedBox(height: 8), Text(l, style: const TextStyle(color: Colors.white70, fontSize: 12)),
  ]));
}

class _OngoingRow extends StatelessWidget {
  final bool muted, videoOn, speakerOn, isVideo, frontCam;
  final VoidCallback onMute, onVideo, onFlip, onSpeaker, onHangUp;
  const _OngoingRow({required this.muted, required this.videoOn, required this.speakerOn, required this.isVideo, required this.frontCam, required this.onMute, required this.onVideo, required this.onFlip, required this.onSpeaker, required this.onHangUp});
  @override Widget build(BuildContext _) => Container(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 44),
    decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black.withOpacity(0.85), Colors.transparent])),
    child: Column(children: [
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _Ctrl(speakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded, 'Speaker', speakerOn, onSpeaker),
        if (isVideo) _Ctrl(videoOn ? Icons.videocam_rounded : Icons.videocam_off_rounded, 'Camera', videoOn, onVideo),
        if (isVideo) _Ctrl(Icons.flip_camera_ios_rounded, 'Flip', true, onFlip),
        _Ctrl(Icons.message_rounded, 'Message', true, () {}),
        _Ctrl(Icons.person_add_rounded, 'Add', true, () {}),
      ]),
      const SizedBox(height: 18),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _Ctrl(muted ? Icons.mic_off_rounded : Icons.mic_rounded, 'Mute', !muted, onMute, sz: 60),
        GestureDetector(onTap: onHangUp, child: Container(width: 70, height: 70, decoration: BoxDecoration(color: Colors.red, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.5), blurRadius: 16, spreadRadius: 2)]), child: const Icon(Icons.call_end_rounded, color: Colors.white, size: 30))),
        const SizedBox(width: 60),
      ]),
    ]),
  );
}
class _Ctrl extends StatelessWidget {
  final IconData i; final String l; final bool active; final VoidCallback t; final double sz;
  const _Ctrl(this.i, this.l, this.active, this.t, {this.sz = 52});
  @override Widget build(BuildContext _) => GestureDetector(onTap: t, child: Column(children: [
    Container(width: sz, height: sz, decoration: BoxDecoration(color: active ? Colors.white.withOpacity(0.18) : Colors.white.withOpacity(0.06), shape: BoxShape.circle), child: Icon(i, color: active ? Colors.white : Colors.white38, size: sz*0.44)),
    const SizedBox(height: 5), Text(l, style: const TextStyle(color: Colors.white60, fontSize: 11)),
  ]));
}
