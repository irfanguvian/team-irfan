import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { parsePagination } from '../common/pagination';
import { dayKeyInZone } from '../common/date.util';

@Injectable()
export class CustomersService {
  constructor(private readonly prisma: PrismaService) {}

  async list(query: { page?: unknown; limit?: unknown }) {
    const { page, limit, skip } = parsePagination(query);

    const customers = await this.prisma.customer.findMany({
      skip,
      take: limit,
      orderBy: { id: 'asc' },
      include: { _count: { select: { invoices: true } } },
    });

    const data = customers.map((c) => ({
      id: c.id,
      name: c.name,
      email: c.email,
      timeZone: c.timeZone,
      invoiceCount: c._count.invoices,
    }));

    const total = await this.prisma.customer.count();
    return { data, page, limit, total };
  }

  /** Daily activity for one customer, bucketed by their local calendar day. */
  async activity(customerId: number) {
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
