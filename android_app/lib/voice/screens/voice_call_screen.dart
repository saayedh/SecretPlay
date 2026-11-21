import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../webrtc_service.dart';
import '../../chat/screens/private_chat_screen.dart';
import '../../core/app_localizations.dart';
import '../../networking/network_mode.dart';
import '../../security/auto_lock_service.dart';

class VoiceCallScreen extends ConsumerStatefulWidget {
  final bool isIncoming;
  final bool isVideoCall;
  final String? initialPeerDeviceId;
  final String? peerPublicKeyBase64;
  final String? peerDisplayName;

  const VoiceCallScreen({
    super.key,
    this.isIncoming = false,
    this.isVideoCall = false,
    this.initialPeerDeviceId,
    this.peerPublicKeyBase64,
    this.peerDisplayName,
  });

  @override
  ConsumerState<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends ConsumerState<VoiceCallScreen> {
  late WebRtcVoiceService _voiceService;

  CallState _callState = CallState.connecting;
  int _durationSeconds = 0;
  bool _isMuted = false;
  bool _isVideoCall = false;
  bool _isCameraEnabled = true;
  AudioRoute _audioRoute = AudioRoute.earpiece;

  String _myId = 'me';
  String _peerId = 'peer';

  StreamSubscription? _stateSub;
  StreamSubscription? _durationSub;
  StreamSubscription? _videoSub;

  @override
  void initState() {
    super.initState();
    _isVideoCall = widget.isVideoCall;
    _isCameraEnabled = widget.isVideoCall;
    _audioRoute = widget.isVideoCall ? AudioRoute.speaker : AudioRoute.earpiece;
    _callState = widget.isIncoming ? CallState.incomingRinging : CallState.connecting;
    if (widget.initialPeerDeviceId != null && widget.initialPeerDeviceId!.isNotEmpty) {
      _peerId = widget.initialPeerDeviceId!;
    }

    final wsClient = ref.read(wsClientProvider);
    final crypto = ref.read(cryptoServiceProvider);
    final autoLock = ref.read(autoLockProvider);

    _voiceService = WebRtcVoiceService(
      wsClient: wsClient,
      cryptoService: crypto,
      autoLockService: autoLock,
    );

    _stateSub = _voiceService.onCallStateChange.listen((state) {
      if (mounted) {
        setState(() {
          _callState = state;
          _isVideoCall = _voiceService.isVideoCall;
          _isCameraEnabled = _voiceService.isCameraEnabled;
        });
        if (state == CallState.ended) {
          Navigator.of(context).pop();
        }
      }
    });

    _durationSub = _voiceService.onCallDuration.listen((dur) {
      if (mounted) {
        setState(() => _durationSeconds = dur);
      }
    });

    _videoSub = _voiceService.onVideoStreamUpdate.listen((_) {
      if (mounted) {
        setState(() {
          _isVideoCall = _voiceService.isVideoCall;
          _isCameraEnabled = _voiceService.isCameraEnabled;
        });
      }
    });

    _initCallContext();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _durationSub?.cancel();
    _videoSub?.cancel();
    _voiceService.dispose();
    super.dispose();
  }

  Future<bool> _ensurePermissions() async {
    if (kIsWeb) {
      // On Web/Desktop Chrome, browser prompts automatically when getUserMedia is invoked
      return true;
    }
    AutoLockService().setAuthenticatingBiometrics(true);
    AutoLockService().setTransientOverlayActive(true);
    try {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) return false;
      if (_isVideoCall) {
        final camStatus = await Permission.camera.request();
        if (!camStatus.isGranted) return false;
      }
      return true;
    } catch (_) {
      return true;
    } finally {
      AutoLockService().setAuthenticatingBiometrics(false);
      AutoLockService().setTransientOverlayActive(false);
    }
  }

  Future<void> _initCallContext() async {
    final keystore = ref.read(keystoreProvider);
    final crypto = ref.read(cryptoServiceProvider);
    final netConfig = ref.read(networkConfigProvider);

    await _voiceService.ensureRenderersInitialized();

    final hasPerm = await _ensurePermissions();
    if (!hasPerm) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('نیاز به دسترسی میکروفون/دوربین برای برقراری تماس است.'),
          ),
        );
        Navigator.of(context).pop();
      }
      return;
    }

    _myId = await keystore.getOrCreateDeviceId();
    final savedPeer = await keystore.getPeerDeviceId();
    if (widget.initialPeerDeviceId != null && widget.initialPeerDeviceId!.isNotEmpty) {
      _peerId = widget.initialPeerDeviceId!;
    } else if (savedPeer != null && savedPeer.isNotEmpty) {
      _peerId = savedPeer;
    }

    final myPriv = await keystore.getIdentityPrivateKey();
    final peerPub = (widget.peerPublicKeyBase64 != null && widget.peerPublicKeyBase64!.isNotEmpty)
        ? widget.peerPublicKeyBase64
        : await keystore.getPeerPublicKey();
    final keyPair = myPriv != null ? await crypto.reconstructIdentityKeyPair(myPriv) : null;

    _voiceService.configureIdentity(
      myDeviceId: _myId,
      peerDeviceId: _peerId,
      networkMode: netConfig.mode,
      myIdentityKeyPair: keyPair,
      peerPublicKeyBase64: peerPub,
      isVideoCall: _isVideoCall,
    );

    if (!widget.isIncoming) {
      await _voiceService.startCall(
        peerDeviceId: _peerId,
        myDeviceId: _myId,
        networkMode: netConfig.mode,
        video: _isVideoCall,
      );
    }
  }

  Future<void> _acceptIncomingCall() async {
    final netConfig = ref.read(networkConfigProvider);
    await _voiceService.acceptCall(
      peerDeviceId: _peerId,
      myDeviceId: _myId,
      networkMode: netConfig.mode,
    );
  }

  Future<void> _rejectIncomingCall() async {
    await _voiceService.rejectCall(
      peerDeviceId: _peerId,
      myDeviceId: _myId,
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _cycleAudioRoute() {
    final nextRoute = switch (_audioRoute) {
      AudioRoute.earpiece => AudioRoute.speaker,
      AudioRoute.speaker => AudioRoute.bluetooth,
      AudioRoute.bluetooth => AudioRoute.earpiece,
    };
    _voiceService.setAudioRoute(nextRoute);
    setState(() => _audioRoute = nextRoute);
  }

  IconData _getAudioRouteIcon() {
    switch (_audioRoute) {
      case AudioRoute.earpiece:
        return Icons.hearing_rounded;
      case AudioRoute.speaker:
        return Icons.volume_up_rounded;
      case AudioRoute.bluetooth:
        return Icons.bluetooth_audio_rounded;
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _getCallStatusText(S s) {
    switch (_callState) {
      case CallState.outgoingRinging:
        return s.tr('در حال زنگ خوردن...', 'RINGING PARTNER...');
      case CallState.incomingRinging:
        return _isVideoCall
            ? s.tr('تماس تصویری رمزنگاری‌شده ورودی...', 'INCOMING ENCRYPTED VIDEO CALL')
            : s.tr('تماس صوتی رمزنگاری‌شده ورودی...', 'INCOMING ENCRYPTED VOICE CALL');
      case CallState.connecting:
        return s.tr('در حال برقراری تونل مستقیم P2P...', 'ESTABLISHING P2P DTLS-SRTP...');
      case CallState.reconnecting:
        return s.tr('در حال بازیابی اتصال...', 'RECONNECTING ICE...');
      case CallState.connected:
        return _formatDuration(_durationSeconds);
      case CallState.ended:
        return s.tr('تماس پایان یافت', 'CALL ENDED');
      case CallState.idle:
        return s.tr('آماده', 'IDLE');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = ref.watch(appLocaleProvider);
    final s = S(lang);
    final hasRemoteVideo = _isVideoCall &&
        _voiceService.remoteRenderer.srcObject != null &&
        _voiceService.remoteRenderer.srcObject!.getVideoTracks().isNotEmpty;
    final hasLocalVideo = _isVideoCall &&
        _voiceService.localRenderer.srcObject != null &&
        _voiceService.localRenderer.srcObject!.getVideoTracks().isNotEmpty;

    return Directionality(
      textDirection: s.dir,
      child: Scaffold(
        backgroundColor: const Color(0xFF060812),
        body: Stack(
          fit: StackFit.expand,
          children: [
            // Ambient Aurora Background when no full-screen video is active
            if (!hasRemoteVideo && !(hasLocalVideo && _isCameraEnabled))
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0.0, -0.35),
                      radius: 1.15,
                      colors: [
                        Color(0xFF1A1F3C),
                        Color(0xFF0A0D1A),
                        Color(0xFF05060B),
                      ],
                    ),
                  ),
                ),
              ),

            // Full-Screen Remote Video View (or Local Preview while ringing before remote arrives!)
            if (hasRemoteVideo)
              Positioned.fill(
                child: RTCVideoView(
                  _voiceService.remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              )
            else if (hasLocalVideo && _isCameraEnabled)
              Positioned.fill(
                child: RTCVideoView(
                  _voiceService.localRenderer,
                  mirror: true,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),

            // Top & Bottom Gradient Scrims for legibility over video
            if (hasRemoteVideo || (hasLocalVideo && _isCameraEnabled))
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.72),
                        Colors.transparent,
                        Colors.black.withOpacity(0.82),
                      ],
                    ),
                  ),
                ),
              ),

            // Floating Local Camera Picture-in-Picture (PiP) Preview when Remote Video is active
            if (hasRemoteVideo && hasLocalVideo && _isCameraEnabled)
              Positioned(
                top: 118,
                right: 18,
                child: GestureDetector(
                  onTap: () => _voiceService.switchCamera(),
                  child: Container(
                    width: 116,
                    height: 168,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF00FFA3), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00FFA3).withOpacity(0.28),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: RTCVideoView(
                        _voiceService.localRenderer,
                        mirror: true,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                    ),
                  ),
                ),
              ),

            // Foreground HUD & Controls
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 30.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Header
                    Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _isVideoCall ? Icons.videocam_rounded : Icons.lock_rounded,
                              color: const Color(0xFF00FFA3),
                              size: 24,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _isVideoCall
                                  ? s.tr('تماس تصویری مستقیم E2EE', 'END-TO-END ENCRYPTED VIDEO')
                                  : s.tr('تماس صوتی مستقیم E2EE', 'END-TO-END ENCRYPTED VOICE'),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        if (widget.peerDisplayName != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            widget.peerDisplayName!,
                            style: const TextStyle(
                              color: Color(0xFF64D2FF),
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          _getCallStatusText(s),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1C1C1E).withOpacity(0.8),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            s.tr(
                              'ارتباط مستقیم P2P DTLS-SRTP • بدون ضبط یا ذخیره روی سرور',
                              'Direct P2P DTLS-SRTP Media • Zero Server Interception',
                            ),
                            style: const TextStyle(color: Color(0xFF00FFA3), fontSize: 10),
                          ),
                        ),
                      ],
                    ),

                    // Center Avatar (shown when audio-only or camera off)
                    if (!hasRemoteVideo && !(hasLocalVideo && _isCameraEnabled))
                      Container(
                        width: 152,
                        height: 152,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF1D2440), Color(0xFF111424)],
                          ),
                          border: Border.all(
                            color: _callState == CallState.connected
                                ? const Color(0xFF00FFA3)
                                : const Color(0xFF00E5FF),
                            width: 2.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: (_callState == CallState.connected
                                      ? const Color(0xFF00FFA3)
                                      : const Color(0xFF00E5FF))
                                  .withOpacity(0.35),
                              blurRadius: 36,
                              spreadRadius: 6,
                            ),
                          ],
                        ),
                        child: Icon(
                          _isVideoCall ? Icons.videocam_rounded : Icons.person_rounded,
                          color: Colors.white70,
                          size: 72,
                        ),
                      )
                    else
                      const SizedBox(height: 80),

                    // Frosted Glass Controls Dock
                    ClipRRect(
                      borderRadius: BorderRadius.circular(32),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111422).withOpacity(0.68),
                            borderRadius: BorderRadius.circular(32),
                            border: Border.all(color: Colors.white.withOpacity(0.12)),
                          ),
                          child: _callState == CallState.incomingRinging
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    IconButton(
                                      iconSize: 34,
                                      icon: const Icon(Icons.call_end_rounded, color: Colors.white),
                                      tooltip: s.tr('رد تماس', 'Reject Call'),
                                      style: IconButton.styleFrom(
                                        backgroundColor: const Color(0xFFFF3B30),
                                        padding: const EdgeInsets.all(20),
                                      ),
                                      onPressed: _rejectIncomingCall,
                                    ),
                                    IconButton(
                                      iconSize: 34,
                                      icon: Icon(
                                        _isVideoCall ? Icons.videocam_rounded : Icons.call_rounded,
                                        color: Colors.black,
                                      ),
                                      tooltip: s.tr('پاسخ به تماس', 'Accept Call'),
                                      style: IconButton.styleFrom(
                                        backgroundColor: const Color(0xFF00FFA3),
                                        padding: const EdgeInsets.all(20),
                                      ),
                                      onPressed: _acceptIncomingCall,
                                    ),
                                  ],
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                  children: [
                                    IconButton(
                                      iconSize: 26,
                                      icon: Icon(
                                        _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                                        color: _isMuted ? const Color(0xFFFF453A) : Colors.white,
                                      ),
                                      tooltip: s.tr('قطع/وصل میکروفون', 'Mute/Unmute'),
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.white.withOpacity(0.08),
                                        padding: const EdgeInsets.all(14),
                                      ),
                                      onPressed: () {
                                        _voiceService.toggleMute();
                                        setState(() => _isMuted = _voiceService.isMuted);
                                      },
                                    ),
                                    if (_isVideoCall) ...[
                                      IconButton(
                                        iconSize: 26,
                                        icon: Icon(
                                          _isCameraEnabled
                                              ? Icons.videocam_rounded
                                              : Icons.videocam_off_rounded,
                                          color: _isCameraEnabled
                                              ? Colors.white
                                              : const Color(0xFFFF453A),
                                        ),
                                        tooltip: s.tr('روشن/خاموش کردن دوربین', 'Toggle Camera'),
                                        style: IconButton.styleFrom(
                                          backgroundColor: Colors.white.withOpacity(0.08),
                                          padding: const EdgeInsets.all(14),
                                        ),
                                        onPressed: () {
                                          _voiceService.toggleCamera();
                                          setState(() =>
                                              _isCameraEnabled = _voiceService.isCameraEnabled);
                                        },
                                      ),
                                      IconButton(
                                        iconSize: 26,
                                        icon: const Icon(Icons.flip_camera_ios_rounded,
                                            color: Colors.white),
                                        tooltip: s.tr('چرخش دوربین جلو/عقب', 'Flip Camera'),
                                        style: IconButton.styleFrom(
                                          backgroundColor: Colors.white.withOpacity(0.08),
                                          padding: const EdgeInsets.all(14),
                                        ),
                                        onPressed: () => _voiceService.switchCamera(),
                                      ),
                                    ],
                                    IconButton(
                                      iconSize: 32,
                                      icon: const Icon(Icons.call_end_rounded, color: Colors.white),
                                      tooltip: s.tr('پایان تماس', 'End Call'),
                                      style: IconButton.styleFrom(
                                        backgroundColor: const Color(0xFFFF3B30),
                                        padding: const EdgeInsets.all(16),
                                      ),
                                      onPressed: () {
                                        _voiceService.endCall(notifyPeer: true);
                                        Navigator.of(context).pop();
                                      },
                                    ),
                                    IconButton(
                                      iconSize: 26,
                                      icon: Icon(
                                        _getAudioRouteIcon(),
                                        color: _audioRoute != AudioRoute.earpiece
                                            ? const Color(0xFF00E5FF)
                                            : Colors.white,
                                      ),
                                      tooltip: s.tr('خروجی صدا', 'Audio Route'),
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.white.withOpacity(0.08),
                                        padding: const EdgeInsets.all(14),
                                      ),
                                      onPressed: _cycleAudioRoute,
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
