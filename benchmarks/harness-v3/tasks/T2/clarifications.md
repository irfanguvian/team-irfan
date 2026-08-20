Q: What fields should a refund item have?
A: Mirror the invoice list item — the model's own scalar fields, createdAt as an ISO string. Do not nest the whole invoice inside it.

Q: What should happen for an invoice id that does not exist?
A: 404.

Q: What envelope should the list use?
A: The same one the invoices list already uses.

Q: Should I add a new module or extend the invoices one?
A: Use your judgement.

Q: Do I need a Prisma migration?
A: No. The Refund model already exists.
