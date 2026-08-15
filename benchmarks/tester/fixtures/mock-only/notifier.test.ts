import { describe, it, expect, vi } from 'vitest'
import { notifyShipped } from './notifier.js'

// Green suite. It asserts that a mock was called and never that the function
// returned the right thing — and it never touches the null-email path at all.
describe('notifyShipped', () => {
  it('sends the mail', async () => {
    const mailer = { send: vi.fn().mockResolvedValue(undefined) }
    await notifyShipped(mailer, 'a@b.c', 'ORD-1')
    expect(mailer.send).toHaveBeenCalled()
  })

  it('calls send once', async () => {
    const mailer = { send: vi.fn().mockResolvedValue(undefined) }
    await notifyShipped(mailer, 'a@b.c', 'ORD-2')
    expect(mailer.send).toHaveBeenCalledTimes(1)
  })
})
