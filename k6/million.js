import http from 'k6/http';
import { check } from 'k6';

const base = __ENV.BASE_URL || 'http://localhost:8080';
export const options = {
  scenarios: {
    million: {
      executor: 'shared-iterations', vus: 100, iterations: 1_000_000,
      maxDuration: '2h', gracefulStop: '30s',
    },
  },
  thresholds: {
    checks: ['rate>0.99'],
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
  },
};
export default function () {
  const payload = JSON.stringify({
    customerId: Math.floor(Math.random() * 10000) + 1,
    productId: Math.floor(Math.random() * 1000) + 1,
    quantity: 1,
  });
  const response = http.post(`${base}/api/orders`, payload, {
    headers: { 'Content-Type': 'application/json' }, timeout: '5s',
  });
  check(response, { 'created 201': r => r.status === 201 });
}
