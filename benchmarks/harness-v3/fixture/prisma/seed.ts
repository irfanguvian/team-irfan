// Deterministic seed. No randomness anywhere — every worktree gets byte-identical
// rows, so a query-count or ordering assertion means the same thing in every run.
import { PrismaClient } from '@prisma/client';

const CUSTOMERS = [
  { name: 'Aster Corp', email: 'aster@example.com', timeZone: 'Asia/Jakarta' },
  { name: 'Borneo Ltd', email: 'borneo@example.com', timeZone: 'Asia/Jakarta' },
  { name: 'Cendana BV', email: 'cendana@example.com', timeZone: 'Pacific/Auckland' },
  { name: 'Damar Inc', email: 'damar@example.com', timeZone: 'America/New_York' },
  { name: 'Elang GmbH', email: 'elang@example.com', timeZone: 'UTC' },
];

// 2026-01-01T00:00:00Z, then one invoice per hour. Fixed epoch, no Date.now().
const EPOCH = Date.parse('2026-01-01T00:00:00.000Z');

export async function seed(prisma: PrismaClient) {
  await prisma.refund.deleteMany();
  await prisma.invoice.deleteMany();
  await prisma.transaction.deleteMany();
  await prisma.customer.deleteMany();

  await prisma.customer.createMany({ data: CUSTOMERS });
  const customers = await prisma.customer.findMany({ orderBy: { id: 'asc' } });

  await prisma.invoice.createMany({
    data: Array.from({ length: 60 }, (_, i) => ({
      number: `INV-${String(i + 1).padStart(4, '0')}`,
      amountCents: 100_000 + i * 1_000,
      currency: 'IDR',
      status: i % 5 === 0 ? 'paid' : 'open',
      createdAt: new Date(EPOCH + i * 3_600_000),
      customerId: customers[i % customers.length].id,
    })),
  });

  const first = await prisma.invoice.findUniqueOrThrow({ where: { number: 'INV-0001' } });
  await prisma.refund.createMany({
    data: Array.from({ length: 25 }, (_, i) => ({
      amountCents: 1_000 * (i + 1),
      reason: `reason-${i + 1}`,
      createdAt: new Date(EPOCH + i * 60_000),
      invoiceId: first.id,
    })),
  });

  // Transactions straddling midnight in several zones — the reports task lives here.
  await prisma.transaction.createMany({
    data: [
      { amountCents: 1_000, occurredAt: new Date('2026-03-02T16:30:00.000Z'), customerId: customers[0].id },
      { amountCents: 2_000, occurredAt: new Date('2026-03-02T17:30:00.000Z'), customerId: customers[0].id },
      { amountCents: 4_000, occurredAt: new Date('2026-03-03T02:00:00.000Z'), customerId: customers[0].id },
      { amountCents: 8_000, occurredAt: new Date('2026-03-02T10:30:00.000Z'), customerId: customers[2].id },
      { amountCents: 16_000, occurredAt: new Date('2026-03-02T11:30:00.000Z'), customerId: customers[2].id },
      { amountCents: 32_000, occurredAt: new Date('2026-03-03T03:30:00.000Z'), customerId: customers[3].id },
      { amountCents: 64_000, occurredAt: new Date('2026-03-03T05:30:00.000Z'), customerId: customers[3].id },
    ],
  });
}

if (typeof require !== 'undefined' && require.main === module) {
  const prisma = new PrismaClient();
  seed(prisma)
    .then(() => prisma.$disconnect())
    .catch(async (e) => {
      console.error(e);
      await prisma.$disconnect();
      process.exit(1);
    });
}
