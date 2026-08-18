# A correct T3 fix: one joined read instead of a query per row. Shape unchanged.
import pathlib, sys
r = pathlib.Path(sys.argv[1])
p = r / 'src/invoices/invoices.service.ts'
s = p.read_text()
old_start = s.index("    const invoices = await this.prisma.invoice.findMany({")
old_end = s.index("    const total = await this.prisma.invoice.count();")
s = s[:old_start] + """    const invoices = await this.prisma.invoice.findMany({
      skip,
      take: limit,
      orderBy: { createdAt: 'desc' },
      include: { customer: true },
    });

    const data = invoices.map((invoice) => ({
      id: invoice.id,
      number: invoice.number,
      amountCents: invoice.amountCents,
      currency: invoice.currency,
      status: invoice.status,
      createdAt: invoice.createdAt.toISOString(),
      customer: invoice.customer
        ? { id: invoice.customer.id, name: invoice.customer.name, email: invoice.customer.email }
        : null,
    }));

""" + s[old_end:]
p.write_text(s)
