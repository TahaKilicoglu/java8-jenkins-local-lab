import http from 'k6/http';
import { check } from 'k6';

const base = __ENV.BASE_URL || 'http://localhost:8080';
export const options = { vus: 1, iterations: 1, thresholds: { checks: ['rate==1'] } };
export default function () {
  const ping = http.get(`${base}/api/orders/ping`);
  check(ping, { 'ping 200': r => r.status === 200 });
  const order = http.post(`${base}/api/orders`, JSON.stringify({ customerId: 123, productId: 500, quantity: 1 }), {
    headers: { 'Content-Type': 'application/json' }, timeout: '5s',
  });
  check(order, { 'order 201': r => r.status === 201 });
}
