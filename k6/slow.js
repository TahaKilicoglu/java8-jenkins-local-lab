import http from 'k6/http';
import { check } from 'k6';

const base = __ENV.BASE_URL || 'http://localhost:8080';
export const options = {
  scenarios: {
    slow: {
      executor: 'constant-arrival-rate', rate: Number(__ENV.RATE || '150'),
      timeUnit: '1s', duration: __ENV.DURATION || '30s',
      preAllocatedVUs: 200, maxVUs: 500,
    },
  },
  thresholds: { http_req_failed: ['rate<0.05'] },
};
export default function () {
  const response = http.get(`${base}/api/orders/slow`, { timeout: '5s' });
  check(response, { 'slow 200': r => r.status === 200 });
}
