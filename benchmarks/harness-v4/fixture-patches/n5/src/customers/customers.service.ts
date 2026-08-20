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
    });

    const data = [];
    for (const customer of customers) {
      const invoiceCount = await this.prisma.invoice.count({
        where: { customerId: customer.id },
      });
      data.push({
        id: customer.id,
        name: customer.name,
        email: customer.email,
        timeZone: customer.timeZone,
        invoiceCount,
      });
    }

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
