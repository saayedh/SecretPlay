import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../webrtc_service.dart';
import '../../chat/screens/private_chat_screen.dart';
import '../../networking/network_mode.dart';
import '../../security/auto_lock_service.dart';

class VoiceCallScreen extends ConsumerStatefulWidget {
  final bool isIncoming;

  const VoiceCallScreen({super.key, this.isIncoming = false});

  @override
  ConsumerState<VoiceCallScreen> createState() => _VoiceCallScreenState();
}

class _VoiceCallScreenState extends ConsumerState<VoiceCallScreen> {
  late WebRtcVoiceService _voiceService;

  CallState _callState = CallState.connecting;
  int _durationSeconds = 0;
  bool _isMuted = false;
  AudioRoute _audioRoute = AudioRoute.earpiece;

  String _myId = 'me';
  String _peerId = 'peer';

  StreamSubscription? _stateSub;
  StreamSubscription? _durationSub;

  @override
  void initState() {
    super.initState();
    _callState = widget.isIncoming ? CallState.incomingRinging : CallState.connecting;
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
        setState(() => _callState = state);
        if (state == CallState.idle || state == CallState.ended) {
          Navigator.of(context).pop();
        }
      }
    });

    _durationSub = _voiceService.onCallDuration.listen((dur) {
      if (mounted) {
        setState(() => _durationSeconds = dur);
      }
    });

    _initCallContext();
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    _durationSub?.cancel();
    _voiceService.endCall(notifyPeer: true);
    super.dispose();
  }

  Future<void> _initCallContext() async {
    final keystore = ref.read(keystoreProvider);
    final crypto = ref.read(cryptoServiceProvider);
    final netConfig = ref.read(networkConfigProvider);

    // Temporarily guard AutoLock while OS permission dialog is shown
    AutoLockService().setAuthenticatingBiometrics(true);
    final status = await Permission.microphone.request();
    AutoLockService().setAuthenticatingBiometrics(false);

    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission required for voice calls.')),
        );
        Navigator.of(context).pop();
      }
      return;
    }

    _myId = await keystore.getOrCreateDeviceId();
    _peerId = await keystore.getPeerDeviceId() ?? 'peer';
    final myPriv = await keystore.getIdentityPrivateKey();
    final peerPub = await keystore.getPeerPublicKey();
    final keyPair = myPriv != null ? await crypto.reconstructIdentityKeyPair(myPriv) : null;

    _voiceService.configureIdentity(
      myDeviceId: _myId,
      peerDeviceId: _peerId,
      networkMode: netConfig.mode,
      myIdentityKeyPair: keyPair,
      peerPublicKeyBase64: peerPub,
    );

    if (!widget.isIncoming) {
      await _voiceService.startCall(
        peerDeviceId: _peerId,
        myDeviceId: _myId,
        networkMode: netConfig.mode,
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

  String _getCallStatusText() {
    switch (_callState) {
      case CallState.outgoingRinging:
        return 'CALLING PEER...';
      case CallState.incomingRinging:
        return 'INCOMING ENCRYPTED CALL';
      case CallState.connecting:
        return 'ESTABLISHING P2P DTLS-SRTP...';
      case CallState.reconnecting:
        return 'RECONNECTING ICE...';
      case CallState.connected:
        return _formatDuration(_durationSeconds);
      case CallState.ended:
        return 'CALL ENDED';
      case CallState.idle:
        return 'IDLE';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0C),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Header
              Column(
                children: [
                  const Icon(Icons.lock_rounded, color: Color(0xFF64D2FF), size: 32),
                  const SizedBox(height: 12),
                  const Text(
                    'END-TO-END ENCRYPTED VOICE',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getCallStatusText(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C1E),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Direct P2P DTLS-SRTP Media • Zero Server Interception',
                      style: TextStyle(color: Color(0xFF00FFA3), fontSize: 10),
                    ),
                  ),
                ],
              ),

              // Animated Soundwave Visualizer / Avatar
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF1C1C1E),
                  border: Border.all(
                    color: _callState == CallState.connected
                        ? const Color(0xFF00FFA3)
                        : const Color(0xFF64D2FF),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (_callState == CallState.connected
                              ? const Color(0xFF00FFA3)
                              : const Color(0xFF64D2FF))
                          .withOpacity(0.25),
                      blurRadius: 24,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: const Icon(Icons.person, color: Colors.white54, size: 72),
              ),

              // Controls Bar (Incoming Ringing vs Active/Outgoing Call)
              if (_callState == CallState.incomingRinging)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Reject Call Button
                    IconButton(
                      iconSize: 36,
                      icon: const Icon(Icons.call_end_rounded, color: Colors.white),
                      tooltip: 'Reject Call',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFFF3B30),
                        padding: const EdgeInsets.all(20),
                      ),
                      onPressed: _rejectIncomingCall,
                    ),
                    // Accept Call Button
                    IconButton(
                      iconSize: 36,
                      icon: const Icon(Icons.call_rounded, color: Colors.black),
                      tooltip: 'Accept Encrypted Call',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF00FFA3),
                        padding: const EdgeInsets.all(20),
                      ),
                      onPressed: _acceptIncomingCall,
                    ),
                  ],
                )
              else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Mute Button
                    IconButton(
                      iconSize: 32,
                      icon: Icon(
                        _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        color: _isMuted ? const Color(0xFFFF453A) : Colors.white,
                      ),
                      tooltip: _isMuted ? 'Unmute Microphone' : 'Mute Microphone',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF1C1C1E),
                        padding: const EdgeInsets.all(16),
                      ),
                      onPressed: () {
                        _voiceService.toggleMute();
                        setState(() => _isMuted = _voiceService.isMuted);
                      },
                    ),

                    // End Call Button
                    IconButton(
                      iconSize: 36,
                      icon: const Icon(Icons.call_end_rounded, color: Colors.white),
                      tooltip: 'End Call',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFFFF3B30),
                        padding: const EdgeInsets.all(20),
                      ),
                      onPressed: () {
                        _voiceService.endCall(notifyPeer: true);
                        Navigator.of(context).pop();
                      },
                    ),

                    // Audio Route (Earpiece / Speaker / Bluetooth) Button
                    IconButton(
                      iconSize: 32,
                      icon: Icon(
                        _getAudioRouteIcon(),
                        color: _audioRoute != AudioRoute.earpiece
                            ? const Color(0xFF64D2FF)
                            : Colors.white,
                      ),
                      tooltip: 'Audio Route: ${_audioRoute.name.toUpperCase()}',
                      style: IconButton.styleFrom(
                        backgroundColor: const Color(0xFF1C1C1E),
                        padding: const EdgeInsets.all(16),
                      ),
                      onPressed: _cycleAudioRoute,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
