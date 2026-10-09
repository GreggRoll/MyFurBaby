import { isIP } from 'node:net';

export function clientIP(request, trustRailwayProxy = false) {
  // Enable only behind Railway's HTTP ingress; do not expose a raw TCP proxy.
  // The edge supplies X-Real-IP. Arbitrary forwarded headers are ignored locally.
  const forwarded = request.headers['x-real-ip'];
  if (trustRailwayProxy && typeof forwarded === 'string' && isIP(forwarded.trim())) return forwarded.trim();
  return request.socket.remoteAddress ?? 'unknown';
}
