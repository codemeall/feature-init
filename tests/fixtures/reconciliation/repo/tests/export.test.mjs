import test from 'node:test';
import assert from 'node:assert/strict';
import { exportReport } from '../src/export.mjs';

test('keeps visible-row order and escapes CSV cells', () => {
  const csv = exportReport([
    { name: 'Beta,"quoted"', date: '2026-10-01', visible: true },
    { name: 'Hidden', date: '2026-10-02', visible: false },
    { name: 'Alpha\nsecond line', date: '2026-10-03', visible: true },
  ]);
  assert.equal(csv, 'name,date\n"Beta,""quoted""","2026-10-01T00:00:00.000Z"\n"Alpha\nsecond line","2026-10-03T00:00:00.000Z"');
});
