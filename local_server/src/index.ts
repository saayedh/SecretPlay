import Fastify from 'fastify';
import fastifyWebsocket from '@fastify/websocket';
import fastifyCors from '@fastify/cors';
import dotenv from 'dotenv';
import qrcode from 'qrcode-terminal';
import { WebSocket, RawData } from 'ws';
import { getLocalIPv4Addresses, isPrivateOrLoopbackIp } from './network';
import { SessionManager } from './session';
import { SecretPlayMessage } from './protocols/protocol';

dotenv.config();

const PORT = parseInt(process.env.PORT || '8787', 10);
const HOST = process.env.HOST || '0.0.0.0';
const HEARTBEAT_INTERVAL_MS = parseInt(process.env.HEARTBEAT_INTERVAL_MS || '5000', 10);
const SESSION_TIMEOUT_MS = parseInt(process.env.SESSION_TIMEOUT_MS || '20000', 10);

const fastify = Fastify({
  logger: false, // Zero operational logs for privacy
});

const sessionManager = new SessionManager(SESSION_TIMEOUT_MS, HEARTBEAT_INTERVAL_MS);

async function start() {
  await fastify.register(fastifyCors, { origin: '*' });
  await fastify.register(fastifyWebsocket);

  // Enforce private LAN / Hotspot IP restriction so the local server is never publicly accessible
  fastify.addHook('onRequest', async (request, reply) => {
    const remoteIp = request.ip || request.socket?.remoteAddress;
    if (!isPrivateOrLoopbackIp(remoteIp)) {
      reply.code(403).send({
        error: 'Forbidden: SecretPlay Local Server accepts connections from private LAN/Hotspot interfaces only.',
      });
    }
  });

  // Health check endpoint
  fastify.get('/health', async () => {
    return {
      status: 'healthy',
      mode: 'local_offline',
      e2ee: true,
      zeroStorage: true,
      timestamp: Date.now(),
    };
  });

  // Status endpoint
  fastify.get('/status', async () => {
    return sessionManager.getStatus();
  });

  // Local server QR pairing info endpoint (LAN only)
  fastify.get('/pair-info', async () => {
    const localIps = getLocalIPv4Addresses();
    const primaryIp = localIps[0]?.address || '127.0.0.1';
    const tokenInfo = sessionManager.getOrRotateServerToken();
    return {
      wsUrl: `ws://${primaryIp}:${PORT}/ws`,
      mode: 'local',
      serverToken: tokenInfo.token,
      expiresAt: tokenInfo.expiresAt,
      interfaces: localIps,
    };
  });

  // Reset endpoint for testing & re-pairing
  fastify.post('/reset', async () => {
    sessionManager.resetPairing();
    return { success: true, message: 'Local pairing and active sessions reset.' };
  });

  // WebSocket route
  fastify.get('/ws', { websocket: true }, (socket: WebSocket) => {
    const ws = socket;
    let registeredDeviceId: string | null = null;

    ws.on('message', (rawData: RawData) => {
      let msg: SecretPlayMessage;
      try {
        msg = JSON.parse(rawData.toString());
      } catch {
        ws.send(
          JSON.stringify({
            type: 'terminate',
            version: 1,
            reason: 'security_alert',
            senderDeviceId: 'server',
            timestamp: Date.now(),
          })
        );
        ws.close(1008, 'Malformed JSON');
        return;
      }

      if (registeredDeviceId && msg.type !== 'auth' && !sessionManager.checkRateLimit(ws, registeredDeviceId)) {
        return;
      }

      switch (msg.type) {
        case 'auth':
          registeredDeviceId = msg.deviceId;
          sessionManager.handleAuth(ws, msg);
          break;

        case 'ping':
          if (registeredDeviceId) {
            sessionManager.handlePing(ws, registeredDeviceId);
          }
          break;

        case 'msg':
          sessionManager.handleMessage(ws, msg);
          break;

        case 'signal':
          sessionManager.handleSignaling(ws, msg);
          break;

        case 'pairing_init':
          registeredDeviceId = msg.deviceAId;
          sessionManager.handlePairingInit(ws, msg);
          break;

        case 'pairing_claim':
          registeredDeviceId = msg.deviceBId;
          sessionManager.handlePairingClaim(ws, msg);
          break;

        case 'revoke':
          sessionManager.handleRevoke(ws, msg);
          break;

        case 'terminate':
          if (registeredDeviceId) {
            sessionManager.terminateSession(registeredDeviceId, msg.reason);
          }
          break;
      }
    });

    ws.on('close', () => {
      sessionManager.handleSocketClose(ws);
    });

    ws.on('error', (err: Error) => {
      console.error('[LocalServer] Socket error:', err.message);
      sessionManager.handleSocketClose(ws);
    });
  });

  try {
    await fastify.listen({ port: PORT, host: HOST });

    const localIps = getLocalIPv4Addresses();
    const primaryIp = localIps[0]?.address || '127.0.0.1';
    const serverUrl = `ws://${primaryIp}:${PORT}/ws`;
    const tokenInfo = sessionManager.getOrRotateServerToken();
    const qrPayload = JSON.stringify({
      wsUrl: serverUrl,
      mode: 'local',
      serverToken: tokenInfo.token,
      ts: Date.now(),
    });

    console.log('===============================================================');
    console.log('   SECRETPLAY OFFLINE LOCAL COORDINATION SERVER (WINDOWS)     ');
    console.log('===============================================================');
    console.log(`Port:             ${PORT}`);
    console.log(`Bound to:         ${HOST} (Private LAN/Hotspot filter active)`);
    console.log(`Local LAN IP(s):  ${localIps.map((i) => `${i.name}: ${i.address}`).join(' | ')}`);
    console.log(`Primary WS URL:   ${serverUrl}`);
    console.log(`Health Check:     http://${primaryIp}:${PORT}/health`);
    console.log(`Pairing Token:    ${tokenInfo.token} (TTL: 15 min)`);
    console.log('---------------------------------------------------------------');
    console.log('Scan the QR code below from the SecretPlay Android app:');
    console.log('---------------------------------------------------------------');

    // Display pairing / connection QR code directly in the terminal
    qrcode.generate(qrPayload, { small: true });

    console.log('---------------------------------------------------------------');
    console.log('Direct URL fallback: ' + serverUrl);
    console.log('Press Ctrl+C or run stop-local.bat to shut down the server.');
    console.log('===============================================================');
  } catch (err) {
    console.error('Fatal error starting local server:', err);
    process.exit(1);
  }
}

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log('\n[LocalServer] Shutting down...');
  sessionManager.dispose();
  await fastify.close();
  process.exit(0);
});

process.on('SIGTERM', async () => {
  sessionManager.dispose();
  await fastify.close();
  process.exit(0);
});

start();
