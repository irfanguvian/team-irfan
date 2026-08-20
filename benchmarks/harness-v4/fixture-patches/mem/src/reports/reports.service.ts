import { Injectable, NotFoundException } from '@nestjs/common';
import { Transaction } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { dayKeyInZone } from '../common/date.util';

@Injectable()
export class ReportsService {
  constructor(private readonly prisma: PrismaService) {}

  /** Daily totals for every customer that has transactions, one entry each. */
  async dailyOverview() {
    const customers = await this.prisma.customer.findMany({ orderBy: { id: 'asc' } });

    const data = [];
    for (const customer of customers) {
      const transactions = await this.prisma.transaction.findMany({
        where: { customerId: customer.id },
        orderBy: { occurredAt: 'asc' },
      });
      if (transactions.length === 0) continue;
      data.push({
        customerId: customer.id,
        timeZone: customer.timeZone,
        days: this.bucketByDay(transactions, customer.timeZone),
      });
    }
    return { data };
  }

  /** Daily totals for one customer, bucketed by that customer's local calendar day. */
  async daily(customerId: number) {
    const customer = await this.prisma.customer.findUnique({ where: { id: customerId } });
    if (!customer) throw new NotFoundException(`customer ${customerId} not found`);

    const transactions = await this.prisma.transaction.findMany({
      where: { customerId },
      orderBy: { occurredAt: 'asc' },
    });

    return {
      customerId,
      timeZone: customer.timeZone,
      days: this.bucketByDay(transactions, customer.timeZone),
    };
  }

  private bucketByDay(transactions: Transaction[], timeZone: string) {
    const buckets = new Map<string, { day: string; totalCents: number; count: number }>();
    for (const tx of transactions) {
      const day = dayKeyInZone(tx.occurredAt, timeZone);
      const bucket = buckets.get(day) ?? { day, totalCents: 0, count: 0 };
      bucket.totalCents += tx.amountCents;
      bucket.count += 1;
      buckets.set(day, bucket);
    }
    return [...buckets.values()].sort((a, b) => a.day.localeCompare(b.day));
  }
}
