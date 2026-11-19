import crypto from 'node:crypto';
import {
  canonicalAuthString,
  canonicalEnvelopeString,
} from './protocol';

const ED25519_PKCS8_PREFIX = Buffer.from('302e020100300506032b657004220420', 'hex');
const X25519_PKCS8_PREFIX = Buffer.from('302e020100300506032b656e04220420', 'hex');
const ED25519_SPKI_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');
const X25519_SPKI_PREFIX = Buffer.from('302a300506032b656e032100', 'hex');

export const SESSION_KEY_HKDF_INFO = 'SecretPlay-SessionKey-v1';
export const SIGNAL_KEY_HKDF_INFO = 'SecretPlay-SignalKey-v1';
export const RECOVERY_KDF_INFO = 'SecretPlay-Recovery-v1';

export interface IdentityBundle {
  seedBase64: string;
  ed25519PublicKeyBase64: string;
  x25519PublicKeyBase64: string;
  /** Combined 64-byte public bundle: [32B Ed25519 || 32B X25519] */
  publicKeyBase64: string;
}

export interface EncryptedPayloadEnvelope {
  ciphertext: string;
  iv: string;
  authTag: string;
  ephemeralPubKey: string;
  seq: number;
  signature: string;
}

export interface RecoveryPackageData {
  version: string;
  deviceId: string;
  privKey: string;
  pubKey: string;
  peerDeviceId: string;
  peerKey: string;
  requiresReverification: boolean;
  createdAt: number;
}

export interface EncryptedRecoveryVaultData {
  v: number;
  kdf: string;
  c: string;
  s: string;
  n: string;
  m: string;
}

function ed25519PrivateFromSeed(seed: Buffer): crypto.KeyObject {
  if (seed.length !== 32) {
    throw new Error('Identity seed must be exactly 32 bytes');
  }
  return crypto.createPrivateKey({
    key: Buffer.concat([ED25519_PKCS8_PREFIX, seed]),
    format: 'der',
    type: 'pkcs8',
  });
}

function x25519PrivateFromSeed(seed: Buffer): crypto.KeyObject {
  if (seed.length !== 32) {
    throw new Error('Identity seed must be exactly 32 bytes');
  }
  return crypto.createPrivateKey({
    key: Buffer.concat([X25519_PKCS8_PREFIX, seed]),
    format: 'der',
    type: 'pkcs8',
  });
}

export function ed25519PublicFromRaw(rawPub: Buffer): crypto.KeyObject {
  if (rawPub.length !== 32) {
    throw new Error('Ed25519 public key must be 32 bytes');
  }
  return crypto.createPublicKey({
    key: Buffer.concat([ED25519_SPKI_PREFIX, rawPub]),
    format: 'der',
    type: 'spki',
  });
}

export function x25519PublicFromRaw(rawPub: Buffer): crypto.KeyObject {
  if (rawPub.length !== 32) {
    throw new Error('X25519 public key must be 32 bytes');
  }
  return crypto.createPublicKey({
    key: Buffer.concat([X25519_SPKI_PREFIX, rawPub]),
    format: 'der',
    type: 'spki',
  });
}

export function extractEd25519RawPublicKey(combinedOrRawBase64: string): Buffer {
  const bytes = Buffer.from(combinedOrRawBase64, 'base64');
  if (bytes.length === 64 || bytes.length === 32) {
    return bytes.subarray(0, 32);
  }
  throw new Error(`Invalid public key length: ${bytes.length}`);
}

export function extractX25519RawPublicKey(combinedOrRawBase64: string): Buffer {
  const bytes = Buffer.from(combinedOrRawBase64, 'base64');
  if (bytes.length === 64) {
    return bytes.subarray(32, 64);
  }
  if (bytes.length === 32) {
    return bytes;
  }
  throw new Error(`Invalid public key length: ${bytes.length}`);
}

export function generateIdentityBundle(): IdentityBundle {
  const seed = crypto.randomBytes(32);
  return reconstructIdentityBundle(seed.toString('base64'));
}

export function reconstructIdentityBundle(seedBase64: string): IdentityBundle {
  const seed = Buffer.from(seedBase64, 'base64');
  const edPriv = ed25519PrivateFromSeed(seed);
  const xPriv = x25519PrivateFromSeed(seed);

  const edPubRaw = crypto.createPublicKey(edPriv).export({ type: 'spki', format: 'der' }).subarray(-32);
  const xPubRaw = crypto.createPublicKey(xPriv).export({ type: 'spki', format: 'der' }).subarray(-32);
  const combined = Buffer.concat([edPubRaw, xPubRaw]);

  return {
    seedBase64,
    ed25519PublicKeyBase64: edPubRaw.toString('base64'),
    x25519PublicKeyBase64: xPubRaw.toString('base64'),
    publicKeyBase64: combined.toString('base64'),
  };
}

export function signAuthChallenge(
  identity: IdentityBundle,
  deviceId: string,
  nonce: string,
  timestamp: number
): string {
  const edPriv = ed25519PrivateFromSeed(Buffer.from(identity.seedBase64, 'base64'));
  const message = Buffer.from(canonicalAuthString(deviceId, nonce, timestamp), 'utf8');
  return crypto.sign(null, message, edPriv).toString('base64');
}

export function verifyAuthChallenge(params: {
  publicKeyBase64: string;
  deviceId: string;
  nonce: string;
  timestamp: number;
  signatureBase64: string;
  nowMs?: number;
  maxSkewMs?: number;
}): { valid: boolean; reason?: string } {
  const now = params.nowMs ?? Date.now();
  const maxSkew = params.maxSkewMs ?? 60_000;

  if (!Number.isFinite(params.timestamp) || Math.abs(now - params.timestamp) > maxSkew) {
    return { valid: false, reason: 'auth_timestamp_out_of_window' };
  }

  if (!params.nonce || params.nonce.length < 8) {
    return { valid: false, reason: 'invalid_nonce' };
  }

  try {
    const edRaw = extractEd25519RawPublicKey(params.publicKeyBase64);
    const edPub = ed25519PublicFromRaw(edRaw);
    const sig = Buffer.from(params.signatureBase64, 'base64');
    if (sig.length !== 64) {
      return { valid: false, reason: 'invalid_signature_length' };
    }
    const payload = Buffer.from(canonicalAuthString(params.deviceId, params.nonce, params.timestamp), 'utf8');
    const ok = crypto.verify(null, payload, edPub, sig);
    return ok ? { valid: true } : { valid: false, reason: 'invalid_ed25519_signature' };
  } catch {
    return { valid: false, reason: 'signature_verification_error' };
  }
}

export class ReplayGuard {
  private seenNonces: Map<string, number> = new Map();
  private lastSeqByEpoch: Map<string, number> = new Map();
  private readonly ttlMs: number;
  private readonly maxEntries: number;

  constructor(ttlMs = 120_000, maxEntries = 2048) {
    this.ttlMs = ttlMs;
    this.maxEntries = maxEntries;
  }

  public checkAndRecordNonce(nonce: string, nowMs = Date.now()): boolean {
    this.prune(nowMs);
    if (this.seenNonces.has(nonce)) {
      return false;
    }
    this.seenNonces.set(nonce, nowMs + this.ttlMs);
    return true;
  }

  public checkAndAdvanceSeq(epochKey: string, seq: number): boolean {
    if (!Number.isInteger(seq) || seq <= 0) {
      return false;
    }
    const last = this.lastSeqByEpoch.get(epochKey) ?? 0;
    if (seq <= last) {
      return false;
    }
    this.lastSeqByEpoch.set(epochKey, seq);
    return true;
  }

  public resetEpoch(epochKey: string): void {
    this.lastSeqByEpoch.delete(epochKey);
  }

  private prune(nowMs: number): void {
    for (const [k, exp] of this.seenNonces.entries()) {
      if (exp <= nowMs) {
        this.seenNonces.delete(k);
      }
    }
    while (this.seenNonces.size > this.maxEntries) {
      const oldestKey = this.seenNonces.keys().next().value;
      if (oldestKey === undefined) break;
      this.seenNonces.delete(oldestKey);
    }
  }
}

export function encryptEnvelope(params: {
  plaintext: string;
  recipientPublicKeyBase64: string;
  senderIdentity: IdentityBundle;
  sessionEpoch: string;
  seq: number;
  hkdfInfo?: string;
}): EncryptedPayloadEnvelope {
  const eph = crypto.generateKeyPairSync('x25519');
  const ephPubRaw = eph.publicKey.export({ type: 'spki', format: 'der' }).subarray(-32);
  const recipientXPub = x25519PublicFromRaw(extractX25519RawPublicKey(params.recipientPublicKeyBase64));

  const sharedSecret = crypto.diffieHellman({
    privateKey: eph.privateKey,
    publicKey: recipientXPub,
  });

  const salt = Buffer.from(params.sessionEpoch, 'utf8');
  const info = Buffer.from(params.hkdfInfo ?? SESSION_KEY_HKDF_INFO, 'utf8');
  const aesKey = Buffer.from(crypto.hkdfSync('sha256', sharedSecret, salt, info, 32));

  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv('chacha20-poly1305', aesKey, iv, { authTagLength: 16 });
  const ciphertextBuf = Buffer.concat([
    cipher.update(Buffer.from(params.plaintext, 'utf8')),
    cipher.final(),
  ]);
  const authTagBuf = cipher.getAuthTag();

  const ciphertextB64 = ciphertextBuf.toString('base64');
  const ivB64 = iv.toString('base64');

  const senderEdPriv = ed25519PrivateFromSeed(Buffer.from(params.senderIdentity.seedBase64, 'base64'));
  const toSign = Buffer.from(
    canonicalEnvelopeString(ciphertextB64, ivB64, params.seq, params.sessionEpoch),
    'utf8'
  );
  const signatureB64 = crypto.sign(null, toSign, senderEdPriv).toString('base64');

  sharedSecret.fill(0);
  aesKey.fill(0);

  return {
    ciphertext: ciphertextB64,
    iv: ivB64,
    authTag: authTagBuf.toString('base64'),
    ephemeralPubKey: ephPubRaw.toString('base64'),
    seq: params.seq,
    signature: signatureB64,
  };
}

export function decryptEnvelope(params: {
  envelope: EncryptedPayloadEnvelope;
  recipientIdentity: IdentityBundle;
  senderPublicKeyBase64: string;
  sessionEpoch: string;
  lastSeq: number;
  hkdfInfo?: string;
}): string {
  if (!params.sessionEpoch) {
    throw new Error('Missing sessionEpoch');
  }
  if (params.envelope.seq <= params.lastSeq) {
    throw new Error(`Replay attack detected: sequence ${params.envelope.seq} <= ${params.lastSeq}`);
  }

  const senderEdPub = ed25519PublicFromRaw(extractEd25519RawPublicKey(params.senderPublicKeyBase64));
  const signedMsg = Buffer.from(
    canonicalEnvelopeString(
      params.envelope.ciphertext,
      params.envelope.iv,
      params.envelope.seq,
      params.sessionEpoch
    ),
    'utf8'
  );
  const sigBuf = Buffer.from(params.envelope.signature, 'base64');
  const sigValid = crypto.verify(null, signedMsg, senderEdPub, sigBuf);
  if (!sigValid) {
    throw new Error('Signature verification failed: tampered or forged envelope');
  }

  const ephPub = x25519PublicFromRaw(Buffer.from(params.envelope.ephemeralPubKey, 'base64'));
  const recipientXPriv = x25519PrivateFromSeed(Buffer.from(params.recipientIdentity.seedBase64, 'base64'));
  const sharedSecret = crypto.diffieHellman({
    privateKey: recipientXPriv,
    publicKey: ephPub,
  });

  const salt = Buffer.from(params.sessionEpoch, 'utf8');
  const info = Buffer.from(params.hkdfInfo ?? SESSION_KEY_HKDF_INFO, 'utf8');
  const aesKey = Buffer.from(crypto.hkdfSync('sha256', sharedSecret, salt, info, 32));

  const decipher = crypto.createDecipheriv(
    'chacha20-poly1305',
    aesKey,
    Buffer.from(params.envelope.iv, 'base64'),
    { authTagLength: 16 }
  );
  decipher.setAuthTag(Buffer.from(params.envelope.authTag, 'base64'));

  try {
    const plain = Buffer.concat([
      decipher.update(Buffer.from(params.envelope.ciphertext, 'base64')),
      decipher.final(),
    ]);
    return plain.toString('utf8');
  } finally {
    sharedSecret.fill(0);
    aesKey.fill(0);
  }
}

export function computeSasCode(params: {
  pubKeyA: string;
  pubKeyB: string;
  deviceAId?: string;
  deviceBId?: string;
  invitationCode: string;
}): string {
  const itemA = params.deviceAId ? `${params.deviceAId}|${params.pubKeyA}` : params.pubKeyA;
  const itemB = params.deviceBId ? `${params.deviceBId}|${params.pubKeyB}` : params.pubKeyB;
  const sorted = [itemA, itemB].sort();
  const mac = crypto
    .createHmac('sha256', Buffer.from(params.invitationCode, 'utf8'))
    .update(Buffer.from(sorted.join(':'), 'utf8'))
    .digest();

  const code = mac.readUInt32BE(0) % 1_000_000;
  return code.toString().padStart(6, '0');
}

export function exportRecoveryVault(params: {
  identity: IdentityBundle;
  deviceId: string;
  peerDeviceId: string;
  peerPublicKeyBase64: string;
  passphrase: string;
}): string {
  if (params.passphrase.length < 6) {
    throw new Error('Recovery passphrase must be at least 6 characters');
  }
  const salt = crypto.randomBytes(16);
  const nonce = crypto.randomBytes(12);
  const key = crypto.scryptSync(params.passphrase, salt, 32, { N: 16384, r: 8, p: 1 });

  const pkg: RecoveryPackageData = {
    version: '1.0',
    deviceId: params.deviceId,
    privKey: params.identity.seedBase64,
    pubKey: params.identity.publicKeyBase64,
    peerDeviceId: params.peerDeviceId,
    peerKey: params.peerPublicKeyBase64,
    requiresReverification: true,
    createdAt: Date.now(),
  };

  const cipher = crypto.createCipheriv('chacha20-poly1305', key, nonce, { authTagLength: 16 });
  const ciphertext = Buffer.concat([
    cipher.update(Buffer.from(JSON.stringify(pkg), 'utf8')),
    cipher.final(),
  ]);
  const authTag = cipher.getAuthTag();
  key.fill(0);

  const vault: EncryptedRecoveryVaultData = {
    v: 1,
    kdf: 'scrypt-16384-8-1',
    c: ciphertext.toString('base64'),
    s: salt.toString('base64'),
    n: nonce.toString('base64'),
    m: authTag.toString('base64'),
  };
  return JSON.stringify(vault);
}

export function importRecoveryVault(params: {
  serializedVault: string;
  passphrase: string;
}): RecoveryPackageData {
  const vault = JSON.parse(params.serializedVault) as EncryptedRecoveryVaultData;
  const salt = Buffer.from(vault.s, 'base64');
  const nonce = Buffer.from(vault.n, 'base64');
  const ciphertext = Buffer.from(vault.c, 'base64');
  const authTag = Buffer.from(vault.m, 'base64');

  const key = crypto.scryptSync(params.passphrase, salt, 32, { N: 16384, r: 8, p: 1 });
  const decipher = crypto.createDecipheriv('chacha20-poly1305', key, nonce, { authTagLength: 16 });
  decipher.setAuthTag(authTag);

  try {
    const plain = Buffer.concat([decipher.update(ciphertext), decipher.final()]);
    const parsed = JSON.parse(plain.toString('utf8')) as Record<string, unknown>;

    // Enforce zero chat/session recovery invariant
    for (const forbidden of ['messages', 'history', 'chat', 'sessionKeys', 'audio', 'recordings']) {
      if (forbidden in parsed) {
        throw new Error(`Forbidden historical field in recovery package: ${forbidden}`);
      }
    }

    return parsed as unknown as RecoveryPackageData;
  } finally {
    key.fill(0);
  }
}
