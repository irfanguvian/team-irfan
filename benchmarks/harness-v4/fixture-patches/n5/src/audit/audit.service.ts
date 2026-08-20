import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { parsePagination } from '../common/pagination';
import { dayKeyInZone } from '../common/date.util';

@Injectable()
export class AuditService {
  constructor(private readonly prisma: PrismaService) {}

  async list(query: { page?: unknown; limit?: unknown }) {
    const { page, limit, skip } = parsePagination(query);

    const events = await this.prisma.auditEvent.findMany({
      skip,
      take: limit,
      orderBy: { createdAt: 'desc' },
    });

    const data = [];
    for (const e of events) {
      const customer = await this.prisma.customer.findUnique({
        where: { id: e.customerId },
      });
      data.push({
        id: e.id,
        action: e.action,
        entity: e.entity,
        entityId: e.entityId,
        createdAt: e.createdAt.toISOString(),
        customer: customer ? { id: customer.id, name: customer.name } : null,
      });
    }

    const total = await this.prisma.auditEvent.count();
    return { data, page, limit, total };
  }

  /** Event counts for one customer, bucketed by their local calendar day. */
  async summary(customerId: number) {
    const customer = await this.prisma.customer.findUnique({ where: { id: customerId } });
    if (!customer) throw new NotFoundException(`customer ${customerId} not found`);

    const events = await this.prisma.auditEvent.findMany({
      where: { customerId },
      orderBy: { createdAt: 'asc' },
    });

    const buckets = new Map<string, { day: string; count: number }>();
    for (const event of events) {
      const day = dayKeyInZone(event.createdAt, customer.timeZone);
      const bucket = buckets.get(day) ?? { day, count: 0 };
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
