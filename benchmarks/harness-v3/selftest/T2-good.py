# A correct T2 feature: the refunds sub-resource, following the list pattern.
import pathlib, sys
r = pathlib.Path(sys.argv[1])

svc = r / 'src/invoices/invoices.service.ts'
s = svc.read_text()
s = s.replace("""  async create(dto: CreateInvoiceDto) {""",
"""  async listRefunds(invoiceId: number, query: { page?: unknown; limit?: unknown }) {
    await this.findOneOrThrow(invoiceId);
    const { page, limit, skip } = parsePagination(query);
    const [refunds, total] = await this.prisma.$transaction([
      this.prisma.refund.findMany({
        where: { invoiceId },
        skip,
        take: limit,
        orderBy: { createdAt: 'desc' },
      }),
      this.prisma.refund.count({ where: { invoiceId } }),
    ]);
    return {
      data: refunds.map((refund) => ({
        id: refund.id,
        amountCents: refund.amountCents,
        reason: refund.reason,
        createdAt: refund.createdAt.toISOString(),
        invoiceId: refund.invoiceId,
      })),
      page,
      limit,
      total,
    };
  }

  async create(dto: CreateInvoiceDto) {""")
svc.write_text(s)

ctl = r / 'src/invoices/invoices.controller.ts'
s = ctl.read_text()
s = s.replace("import { Body, Controller, Get, HttpCode, Post, Query, UseGuards } from '@nestjs/common';",
              "import { Body, Controller, Get, HttpCode, Param, ParseIntPipe, Post, Query, UseGuards } from '@nestjs/common';")
s = s.replace("""  @Post()""",
"""  @Get(':id/refunds')
  listRefunds(
    @Param('id', ParseIntPipe) id: number,
    @Query() query: { page?: string; limit?: string },
  ) {
    return this.invoices.listRefunds(id, query);
  }

  @Post()""")
ctl.write_text(s)
