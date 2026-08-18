import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { parsePagination } from '../common/pagination';
import { CreateInvoiceDto } from './dto/create-invoice.dto';

@Injectable()
export class InvoicesService {
  constructor(private readonly prisma: PrismaService) {}

  async list(query: { page?: unknown; limit?: unknown }) {
    const { page, limit, skip } = parsePagination(query);

    const invoices = await this.prisma.invoice.findMany({
      skip,
      take: limit,
      orderBy: { createdAt: 'desc' },
    });

    const data = [];
    for (const invoice of invoices) {
      const customer = await this.prisma.customer.findUnique({
        where: { id: invoice.customerId },
      });
      data.push({
        id: invoice.id,
        number: invoice.number,
        amountCents: invoice.amountCents,
        currency: invoice.currency,
        status: invoice.status,
        createdAt: invoice.createdAt.toISOString(),
        customer: customer
          ? { id: customer.id, name: customer.name, email: customer.email }
          : null,
      });
    }

    const total = await this.prisma.invoice.count();

    return { data, page, limit, total };
  }

  async create(dto: CreateInvoiceDto) {
    const invoice = await this.prisma.invoice.create({
      data: {
        number: dto.number,
        amountCents: dto.amountCents,
        currency: dto.currency ?? 'IDR',
        customerId: dto.customerId,
      },
    });
    return { id: invoice.id, number: invoice.number };
  }

  async findOneOrThrow(id: number) {
    const invoice = await this.prisma.invoice.findUnique({ where: { id } });
    if (!invoice) throw new NotFoundException(`invoice ${id} not found`);
    return invoice;
  }
}
