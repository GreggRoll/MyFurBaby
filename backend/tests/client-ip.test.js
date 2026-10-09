import test from 'node:test';
import assert from 'node:assert/strict';
import { clientIP } from '../client-ip.js';

const request = headers => ({ headers, socket: { remoteAddress: '127.0.0.1' } });
test('direct connections cannot bypass free-account limits with forwarded headers', () => {
  assert.equal(clientIP(request({ 'x-real-ip': '203.0.113.5', 'x-forwarded-for': '203.0.113.6' })), '127.0.0.1');
});
test('trusted ingress separates IPv4 and IPv6 clients sharing one proxy', () => {
  assert.equal(clientIP(request({ 'x-real-ip': '203.0.113.5' }), true), '203.0.113.5');
  assert.equal(clientIP(request({ 'x-real-ip': '2001:db8::1' }), true), '2001:db8::1');
});
test('malformed and multi-value ingress addresses use the socket identity', () => {
  for (const value of ['invalid', '203.0.113.1,203.0.113.2', ['203.0.113.1'], undefined]) {
    assert.equal(clientIP(request({ 'x-real-ip': value }), true), '127.0.0.1');
  }
});
