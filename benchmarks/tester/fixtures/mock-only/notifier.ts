export type Mailer = { send: (to: string, body: string) => Promise<void> }

/**
 * Notify a user their order shipped. Returns false without sending when the
 * address is missing — a dropped notification is better than a thrown request.
 */
export async function notifyShipped(
  mailer: Mailer,
  email: string | null,
  orderId: string,
): Promise<boolean> {
  if (!email) return false
  await mailer.send(email, `Order ${orderId} shipped`)
  return true
}
