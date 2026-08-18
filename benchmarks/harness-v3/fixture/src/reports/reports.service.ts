import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { dayKeyInZone } from '../common/date.util';

@Injectable()
export class ReportsService {
  constructor(private readonly prisma: PrismaService) {}

  /** Daily totals for one customer, bucketed by that customer's local calendar day. */
  async daily(customerId: number) {
    const customer = await this.prisma.customer.findUnique({ where: { id: customerId } });
    if (!customer) throw new NotFoundException(`customer ${customerId} not found`);

    const transactions = await this.prisma.transaction.findMany({
      where: { customerId },
      orderBy: { occurredAt: 'asc' },
    });

    const buckets = new Map<string, { day: string; totalCents: number; count: number }>();
    for (const tx of transactions) {
      const day = dayKeyInZone(tx.occurredAt, customer.timeZone);
      const bucket = buckets.get(day) ?? { day, totalCents: 0, count: 0 };
      bucket.totalCents += tx.amountCents;
      bucket.count += 1;
      buckets.set(day, bucket);
    }

    return {
      customerId,
      timeZone: customer.timeZone,
      days: [...buckets.values()].sort((a, b) => a.day.localeCompare(b.day)),
    };
  }
}
