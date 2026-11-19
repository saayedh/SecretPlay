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
          version: '1.2.0',
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
