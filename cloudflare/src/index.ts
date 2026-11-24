import { SecretPlaySessionRelay } from '../durable_objects/SecretPlaySessionRelay';
import { ADMIN_DASHBOARD_HTML } from './admin_dashboard';

export interface Env {
  SESSION_RELAY: DurableObjectNamespace<SecretPlaySessionRelay>;
  ENABLE_CLOUDFLARE_TURN?: string;
  CF_TURN_KEY_ID?: string;
  CF_TURN_API_TOKEN?: string;
}

export { SecretPlaySessionRelay };

function resolveRoomName(url: URL): string {
  const token = url.searchParams.get('token')?.trim().toUpperCase();
  if (token && token.length >= 2 && token.length <= 64) {
    return `room:${token}`;
  }
  return 'primary-pair';
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    // Root status
    if (url.pathname === '/') {
      return new Response(
        JSON.stringify({
          service: 'SecretPlay Cloudflare E2EE Relay',
          version: '2.1.1',
          e2ee: true,
          zeroStorage: true,
          freeTierMode: true,
          multiRoomTokens: true,
          adminDashboard: '/admin',
          turnEnabled: env.ENABLE_CLOUDFLARE_TURN === 'true',
          timestamp: Date.now(),
        }),
        {
          headers: { 'Content-Type': 'application/json' },
        }
      );
    }

    // Interactive Cloudflare Edge Admin Dashboard UI
    if (url.pathname === '/admin' || url.pathname === '/admin/') {
      return new Response(ADMIN_DASHBOARD_HTML, {
        headers: { 'Content-Type': 'text/html; charset=utf-8' },
      });
    }

    // Admin API routes forwarded to central 'admin-registry' Durable Object
    if (url.pathname === '/admin/api/overview') {
      const id = env.SESSION_RELAY.idFromName('admin-registry');
      const stub = env.SESSION_RELAY.get(id);
      const targetUrl = new URL(request.url);
      targetUrl.pathname = '/internal-admin/overview';
      return stub.fetch(new Request(targetUrl.toString(), request));
    }

    if (url.pathname === '/admin/api/command' && request.method === 'POST') {
      const id = env.SESSION_RELAY.idFromName('admin-registry');
      const stub = env.SESSION_RELAY.get(id);
      const targetUrl = new URL(request.url);
      targetUrl.pathname = '/internal-admin/command';
      return stub.fetch(new Request(targetUrl.toString(), request));
    }

    // CORS preflight for Flutter Web / Mobile HTTP calls
    if (request.method === 'OPTIONS') {
      return new Response(null, {
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type, X-Admin-Key',
        },
      });
    }

    // Register device SecretPlay ID (SP-XXX-XXX) + public key in directory on app unlock
    if (url.pathname === '/register' && request.method === 'POST') {
      const id = env.SESSION_RELAY.idFromName('admin-registry');
      const stub = env.SESSION_RELAY.get(id);
      const body = (await request.json()) as Record<string, unknown>;
      const cfCountry = request.headers.get('CF-IPCountry') || 'UN';
      const rawIp = request.headers.get('CF-Connecting-IP') || '0.0.0.0';
      const ipParts = rawIp.split('.');
      const ipMasked =
        ipParts.length === 4 ? `${ipParts[0]}.${ipParts[1]}.*.*` : rawIp.slice(0, 10) + '***';
      const res = await stub.fetch(
        new Request('https://internal/internal-admin/telemetry', {
          method: 'POST',
          body: JSON.stringify({
            event: 'register',
            deviceId: body.deviceId,
            secretNumber: body.secretNumber,
            publicKey: body.publicKey,
            country: cfCountry,
            ipMasked,
            roomToken: 'directory',
          }),
        })
      );
      const json = await res.json();
      return Response.json(json, {
        headers: { 'Access-Control-Allow-Origin': '*' },
      });
    }

    // Lookup peer public key & deviceId by SecretPlay ID (enables offline E2EE messaging!)
    if (url.pathname === '/lookup' && request.method === 'GET') {
      const id = env.SESSION_RELAY.idFromName('admin-registry');
      const stub = env.SESSION_RELAY.get(id);
      const targetUrl = new URL(request.url);
      targetUrl.pathname = '/internal-admin/lookup';
      const res = await stub.fetch(new Request(targetUrl.toString(), request));
      const data = await res.json();
      return Response.json(data, {
        headers: { 'Access-Control-Allow-Origin': '*' },
      });
    }

    // In-App Auto-Update Checker endpoint
    if (url.pathname === '/version' && request.method === 'GET') {
      const id = env.SESSION_RELAY.idFromName('admin-registry');
      const stub = env.SESSION_RELAY.get(id);
      const targetUrl = new URL(request.url);
      targetUrl.pathname = '/internal-admin/version';
      const res = await stub.fetch(new Request(targetUrl.toString(), request));
      const data = await res.json();
      return Response.json(data, {
        headers: { 'Access-Control-Allow-Origin': '*' },
      });
    }

    // Health check endpoint
    if (url.pathname === '/health') {
      const id = env.SESSION_RELAY.idFromName(resolveRoomName(url));
      const stub = env.SESSION_RELAY.get(id);
      return stub.fetch(request);
    }

    // Administrative / explicit revocation route
    if (url.pathname === '/revoke' && request.method === 'POST') {
      const id = env.SESSION_RELAY.idFromName(resolveRoomName(url));
      const stub = env.SESSION_RELAY.get(id);
      return stub.fetch(request);
    }

    // WebSocket route for device pairing and E2EE messaging
    if (url.pathname === '/ws') {
      const id = env.SESSION_RELAY.idFromName(resolveRoomName(url));
      const stub = env.SESSION_RELAY.get(id);
      return stub.fetch(request);
    }

    // Personal per-device WebSocket inbox for 24/7 background notifications, floating heartbeats & holograms
    if (url.pathname === '/inbox-ws') {
      const deviceId = url.searchParams.get('deviceId')?.trim();
      if (!deviceId) {
        return new Response('Missing deviceId', { status: 400 });
      }
      const id = env.SESSION_RELAY.idFromName(`inbox:${deviceId}`);
      const stub = env.SESSION_RELAY.get(id);
      return stub.fetch(request);
    }

    // Push a disguised notification / floating heartbeat / lock-screen hologram to a specific device inbox
    if (url.pathname === '/inbox/push' && request.method === 'POST') {
      try {
        const body = (await request.json()) as Record<string, unknown>;
        const recipientDeviceId =
          typeof body.recipientDeviceId === 'string' ? body.recipientDeviceId.trim() : '';
        if (!recipientDeviceId) {
          return Response.json(
            { ok: false, error: 'Missing recipientDeviceId' },
            { status: 400, headers: { 'Access-Control-Allow-Origin': '*' } }
          );
        }
        const id = env.SESSION_RELAY.idFromName(`inbox:${recipientDeviceId}`);
        const stub = env.SESSION_RELAY.get(id);
        const res = await stub.fetch(
          new Request('https://internal/internal-inbox/push', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(body),
          })
        );
        const data = await res.json();
        return Response.json(data, {
          headers: { 'Access-Control-Allow-Origin': '*' },
        });
      } catch {
        return Response.json(
          { ok: false, error: 'Invalid inbox push payload' },
          { status: 400, headers: { 'Access-Control-Allow-Origin': '*' } }
        );
      }
    }

    // Optional ephemeral TURN credentials endpoint (Free tier / disabled by default)
    if (url.pathname === '/turn') {
      if (env.ENABLE_CLOUDFLARE_TURN !== 'true' || !env.CF_TURN_KEY_ID || !env.CF_TURN_API_TOKEN) {
        return new Response(
          JSON.stringify({
            turnEnabled: false,
            iceServers: [
              { urls: 'stun:stun.cloudflare.com:3478' },
              { urls: 'stun:stun.l.google.com:19302' },
            ],
            note: 'STUN-only mode active (Zero cost). WebRTC media flows direct P2P. TURN relay disabled by policy.',
          }),
          {
            headers: { 'Content-Type': 'application/json' },
          }
        );
      }

      try {
        const turnResponse = await fetch(
          `https://rtc.live.cloudflare.com/v1/turn/keys/${env.CF_TURN_KEY_ID}/credentials/generate-ice-servers`,
          {
            method: 'POST',
            headers: {
              Authorization: `Bearer ${env.CF_TURN_API_TOKEN}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({ ttl: 3600 }),
          }
        );
        if (!turnResponse.ok) {
          throw new Error(`Cloudflare TURN API returned HTTP ${turnResponse.status}`);
        }
        const turnData = (await turnResponse.json()) as Record<string, unknown>;
        return Response.json({
          turnEnabled: true,
          ...turnData,
        });
      } catch (err: unknown) {
        const message = err instanceof Error ? err.message : String(err);
        return new Response(
          JSON.stringify({ error: 'Failed to generate TURN credentials', details: message }),
          {
            status: 500,
            headers: { 'Content-Type': 'application/json' },
          }
        );
      }
    }

    return new Response('Not Found', { status: 404 });
  },
};
