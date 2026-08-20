# The T3 trap: fast, and broken for every consumer — the nested customer is
# flattened away. Must be caught by the contract test, not by the hidden one.
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
    });

    const data = invoices.map((invoice) => ({
      id: invoice.id,
      number: invoice.number,
      amountCents: invoice.amountCents,
      currency: invoice.currency,
      status: invoice.status,
      createdAt: invoice.createdAt.toISOString(),
      customerId: invoice.customerId,
    }));

""" + s[old_end:]
p.write_text(s)
