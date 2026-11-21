/**
 * SecretPlay Unified Communication Protocol
 * Shared between Cloudflare Workers/Durable Objects, Local Server, and Client.
 */

export type ProtocolMessageType =
  | 'auth'
  | 'auth_result'
  | 'session_status'
  | 'msg'
  | 'msg_ack'
  | 'msg_received'
  | 'msg_delivered'
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
  | 'ice_candidate'
  | 'typing_start'
  | 'typing_stop'
  | 'stealth_ping'
  | 'heartbeat_pulse';

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
  ciphertext: string;
  iv: string;
  authTag: string;
  ephemeralPubKey: string;
  seq: number;
  signature: string;
}

export interface MessageAck extends BaseProtocolMessage {
  type: 'msg_ack';
  msgId: string;
  status: 'relayed' | 'delivered' | 'queued_offline' | 'dropped_peer_offline';
}

export interface SignalingMessage extends BaseProtocolMessage {
  type: 'signal';
  signalType: SignalPayloadType;
  senderDeviceId: string;
  recipientDeviceId: string;
  sessionEpoch: string;
  encryptedPayload: string;
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
