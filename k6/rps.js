import http from 'k6/http';
import { check } from 'k6';

const base = __ENV.BASE_URL || 'http://localhost:8080';
const targetRate = Number(__ENV.RATE || '100');
export const options = {
  scenarios: {
    orders: {
      executor: 'constant-arrival-rate', rate: targetRate, timeUnit: '1s',
      duration: __ENV.DURATION || '30s', preAllocatedVUs: 100, maxVUs: 1000,
    },
  },
  thresholds: {
    dropped_iterations: ['count==0'],
    checks: ['rate>0.99'],
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
  },
};
export default function () {
  const response = http.post(`${base}/api/orders`, JSON.stringify({
    customerId: Math.floor(Math.random() * 10000) + 1,
    productId: Math.floor(Math.random() * 1000) + 1,
    quantity: 1,
  }), { headers: { 'Content-Type': 'application/json' }, timeout: '5s' });
  check(response, { 'created 201': r => r.status === 201 });
}
