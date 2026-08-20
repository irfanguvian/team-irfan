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
    });

    const data = [];
    for (const refund of refunds) {
      const invoice = await this.prisma.invoice.findUnique({
        where: { id: refund.invoiceId },
      });
      const customer = invoice
        ? await this.prisma.customer.findUnique({ where: { id: invoice.customerId } })
        : null;
      data.push({
        id: refund.id,
        amountCents: refund.amountCents,
        reason: refund.reason,
        createdAt: refund.createdAt.toISOString(),
        invoice: invoice ? { id: invoice.id, number: invoice.number } : null,
        customer: customer ? { id: customer.id, name: customer.name } : null,
      });
    }

    const total = await this.prisma.refund.count();
    return { data, page, limit, total };
  }
}
