/**
 * SecretPlay Unified Communication Protocol
 * Shared across crypto_core, Cloudflare Workers/Durable Objects, Local Server, and Android Client.
 *
 * Strict E2EE Guarantee:
 * - Ciphertext only for chat messages and WebRTC signaling.
 * - Zero plaintext stored or processed by any relay server.
 * - Volatile, memory-only session state.
 */

export type ProtocolMessageType =
  | 'auth'
  | 'auth_result'
  | 'session_status'
  | 'msg'
  | 'msg_ack'
  | 'signal'
  | 'ping'
  | 'pong'
  | 'terminate'
  | 'pairing_init'
  | 'pairing_claim'
  | 'pairing_verify'
  | 'pairing_confirm'
  | 'revoke'
  | 'revoke_confirm';

export type SignalPayloadType =
  | 'call_request'
  | 'call_accept'
  | 'call_reject'
  | 'call_end'
  | 'offer'
  | 'answer'
  | 'ice_candidate';

export interface BaseProtocolMessage {
  type: ProtocolMessageType;
  version: 1;
  timestamp: number;
}

export interface AuthMessage extends BaseProtocolMessage {
  type: 'auth';
  deviceId: string;
  nonce: string;
  signature: string; // Ed25519 signature of `${deviceId}:${nonce}:${timestamp}`
  pairToken?: string;
  publicKey?: string;
}

export interface AuthResultMessage extends BaseProtocolMessage {
  type: 'auth_result';
  success: boolean;
  deviceId: string;
  peerConnected: boolean;
  sessionEpoch?: string;
  peerDeviceId?: string;
  peerPublicKey?: string;
  pairToken?: string;
  error?: string;
}

export interface SessionStatusMessage extends BaseProtocolMessage {
  type: 'session_status';
  active: boolean;
  peerOnline: boolean;
  sessionEpoch: string;
  peerDeviceId?: string;
  peerPublicKey?: string;
}

export interface EncryptedChatMessage extends BaseProtocolMessage {
  type: 'msg';
  msgId: string;
  senderDeviceId: string;
  recipientDeviceId: string;
  sessionEpoch: string;
  ciphertext: string;      // Base64 ChaCha20-Poly1305 ciphertext
  iv: string;              // Base64 12-byte nonce
  authTag: string;         // Base64 16-byte AEAD authentication tag
  ephemeralPubKey: string; // Base64 32-byte ephemeral X25519 public key
  seq: number;             // Strictly monotonic sequence number
  signature: string;       // Base64 Ed25519 signature over canonical envelope
}

export interface MessageAck extends BaseProtocolMessage {
  type: 'msg_ack';
  msgId: string;
  status: 'relayed' | 'delivered' | 'dropped_peer_offline';
}

export interface SignalingMessage extends BaseProtocolMessage {
  type: 'signal';
  signalType: SignalPayloadType;
  senderDeviceId: string;
  recipientDeviceId: string;
  sessionEpoch: string;
  encryptedPayload: string; // Encrypted SDP or ICE candidate (or empty for ring control)
  iv: string;
  authTag: string;
  seq: number;
  ephemeralPubKey?: string;
  signature?: string;
}

export interface PingMessage extends BaseProtocolMessage {
  type: 'ping';
}

export interface PongMessage extends BaseProtocolMessage {
  type: 'pong';
}

export interface TerminateSessionMessage extends BaseProtocolMessage {
  type: 'terminate';
  reason: 'user_lock' | 'app_backgrounded' | 'manual_exit' | 'timeout' | 'security_alert' | 'peer_disconnected' | 'revoked';
  senderDeviceId: string;
}

export interface PairingInitMessage extends BaseProtocolMessage {
  type: 'pairing_init';
  invitationCode: string;
  deviceAPublicKey: string;
  deviceAId: string;
}

export interface PairingClaimMessage extends BaseProtocolMessage {
  type: 'pairing_claim';
  invitationCode: string;
  deviceBPublicKey: string;
  deviceBId: string;
}

export interface PairingVerifyMessage extends BaseProtocolMessage {
  type: 'pairing_verify';
  sasCode: string;
}

export interface PairingConfirmMessage extends BaseProtocolMessage {
  type: 'pairing_confirm';
  success: boolean;
  error?: string;
  peerDeviceId?: string;
  peerPublicKey?: string;
  sessionEpoch?: string;
}

export interface RevokePairMessage extends BaseProtocolMessage {
  type: 'revoke';
  senderDeviceId: string;
  nonce: string;
  signature: string;
}

export interface RevokeConfirmMessage extends BaseProtocolMessage {
  type: 'revoke_confirm';
  success: boolean;
  revokedBy?: string;
  error?: string;
}

export type SecretPlayMessage =
  | AuthMessage
  | AuthResultMessage
  | SessionStatusMessage
  | EncryptedChatMessage
  | MessageAck
  | SignalingMessage
  | PingMessage
  | PongMessage
  | TerminateSessionMessage
  | PairingInitMessage
  | PairingClaimMessage
  | PairingVerifyMessage
  | PairingConfirmMessage
  | RevokePairMessage
  | RevokeConfirmMessage;

export function canonicalAuthString(deviceId: string, nonce: string, timestamp: number): string {
  return `${deviceId}:${nonce}:${timestamp}`;
}

export function canonicalEnvelopeString(
  ciphertextBase64: string,
  ivBase64: string,
  seq: number,
  sessionEpoch: string
): string {
  return `${ciphertextBase64}:${ivBase64}:${seq}:${sessionEpoch}`;
}
