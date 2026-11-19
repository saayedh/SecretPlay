import os from 'os';

export interface NetworkInterfaceInfo {
  name: string;
  address: string;
}

/**
 * Verifies whether an IPv4 or IPv6 address belongs strictly to a private LAN,
 * Windows Mobile Hotspot, link-local, or loopback interface.
 * Rejects public WAN IP addresses so the local server cannot be exposed publicly.
 */
export function isPrivateOrLoopbackIp(rawIp: string | undefined): boolean {
  if (!rawIp) return false;
  const ip = rawIp.replace(/^::ffff:/i, '').trim();

  if (ip === '::1' || ip === '0:0:0:0:0:0:0:1' || ip.toLowerCase().startsWith('fe80:') || ip.toLowerCase().startsWith('fc') || ip.toLowerCase().startsWith('fd')) {
    return true;
  }

  const parts = ip.split('.').map((p) => Number(p));
  if (parts.length !== 4 || parts.some((n) => !Number.isInteger(n) || n < 0 || n > 255)) {
    return false;
  }

  const [a, b] = parts;
  // Loopback: 127.0.0.0/8
  if (a === 127) return true;
  // RFC1918 Private Class A: 10.0.0.0/8
  if (a === 10) return true;
  // RFC1918 Private Class B: 172.16.0.0/12
  if (a === 172 && b >= 16 && b <= 31) return true;
  // RFC1918 Private Class C & Windows Mobile Hotspot (192.168.137.x): 192.168.0.0/16
  if (a === 192 && b === 168) return true;
  // Link-local APIPA: 169.254.0.0/16
  if (a === 169 && b === 254) return true;

  return false;
}

/**
 * Discovers non-internal IPv4 network interfaces on the Windows host.
 * Prioritizes Windows Mobile Hotspot (192.168.137.x) and Wi-Fi/Ethernet LAN interfaces
 * (192.168.x.x, 10.x.x.x, 172.16-31.x.x).
 */
export function getLocalIPv4Addresses(): NetworkInterfaceInfo[] {
  const interfaces = os.networkInterfaces();
  const preferred: NetworkInterfaceInfo[] = [];
  const secondary: NetworkInterfaceInfo[] = [];

  for (const [name, addrs] of Object.entries(interfaces)) {
    if (!addrs) continue;
    for (const addr of addrs) {
      if (addr.family === 'IPv4' && !addr.internal && isPrivateOrLoopbackIp(addr.address)) {
        const isVirtual = /vEthernet|VirtualBox|VMware|WSL|Tailscale|WireGuard/i.test(name);
        const isHotspot = addr.address.startsWith('192.168.137.');
        if (isHotspot) {
          preferred.unshift({ name, address: addr.address });
        } else if (!isVirtual) {
          preferred.push({ name, address: addr.address });
        } else {
          secondary.push({ name, address: addr.address });
        }
      }
    }
  }

  const results = [...preferred, ...secondary];
  if (results.length === 0) {
    results.push({ name: 'Loopback', address: '127.0.0.1' });
  }

  return results;
}
