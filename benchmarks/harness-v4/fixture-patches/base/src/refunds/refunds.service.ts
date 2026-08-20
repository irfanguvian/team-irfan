import { Injectable } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { parsePagination } from '../common/pagination';

@Injectable()
export class RefundsService {
  constructor(private readonly prisma: PrismaService) {}

  async list(query: { page?: unknown; limit?: unknown }) {
    const { page, limit, skip } = parsePagination(query);

    const refunds = await this.prisma.refund.findMany({
      skip,
      take: limit,
      orderBy: { createdAt: 'desc' },
      include: { invoice: { include: { customer: true } } },
    });

    const data = refunds.map((r) => ({
      id: r.id,
      amountCents: r.amountCents,
      reason: r.reason,
      createdAt: r.createdAt.toISOString(),
      invoice: { id: r.invoice.id, number: r.invoice.number },
      customer: { id: r.invoice.customer.id, name: r.invoice.customer.name },
    }));

    const total = await this.prisma.refund.count();
    return { data, page, limit, total };
  }
}
