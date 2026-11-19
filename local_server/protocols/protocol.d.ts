/**
 * SecretPlay Unified Communication Protocol
 * Shared between Cloudflare Workers/Durable Objects, Local Server, and Client.
 *
 * Strict E2EE Guarantee:
 * - Ciphertext only for chat messages and WebRTC signaling.
 * - Zero plaintext stored or processed by any server.
 * - Volatile, memory-only session state.
 */
export type ProtocolMessageType = 'auth' | 'auth_result' | 'session_status' | 'msg' | 'msg_ack' | 'signal' | 'ping' | 'pong' | 'terminate' | 'pairing_init' | 'pairing_claim' | 'pairing_verify' | 'pairing_confirm';
export type SignalPayloadType = 'call_request' | 'call_accept' | 'call_reject' | 'call_end' | 'offer' | 'answer' | 'ice_candidate';
export interface BaseProtocolMessage {
    type: ProtocolMessageType;
    version: 1;
    timestamp: number;
}
export interface AuthMessage extends BaseProtocolMessage {
    type: 'auth';
    deviceId: string;
    nonce: string;
    signature: string;
}
export interface AuthResultMessage extends BaseProtocolMessage {
    type: 'auth_result';
    success: boolean;
    deviceId: string;
    peerConnected: boolean;
    sessionEpoch?: string;
    error?: string;
}
export interface SessionStatusMessage extends BaseProtocolMessage {
    type: 'session_status';
    active: boolean;
    peerOnline: boolean;
    sessionEpoch: string;
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
    status: 'relayed' | 'delivered';
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
}
export interface PingMessage extends BaseProtocolMessage {
    type: 'ping';
}
export interface PongMessage extends BaseProtocolMessage {
    type: 'pong';
}
export interface TerminateSessionMessage extends BaseProtocolMessage {
    type: 'terminate';
    reason: 'user_lock' | 'app_backgrounded' | 'manual_exit' | 'timeout' | 'security_alert';
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
}
export type SecretPlayMessage = AuthMessage | AuthResultMessage | SessionStatusMessage | EncryptedChatMessage | MessageAck | SignalingMessage | PingMessage | PongMessage | TerminateSessionMessage | PairingInitMessage | PairingClaimMessage | PairingVerifyMessage | PairingConfirmMessage;
