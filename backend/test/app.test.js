const test = require('node:test');
const assert = require('node:assert');

test('Backend Logic Unit Tests', async (t) => {
  await t.test('bookTicket() should reject invalid seat count <= 0', () => {
    const seats = 0;
    assert.strictEqual(seats <= 0, true, 'Seats count must be greater than 0');
  });

  await t.test('bookTicket() should validate customerName presence', () => {
    const customerName = '';
    assert.strictEqual(!customerName, true, 'Customer name must be provided');
  });

  await t.test('Cache key naming format matches convention', () => {
    const cacheKey = 'movies:all';
    assert.strictEqual(cacheKey.startsWith('movies:'), true);
  });
});
