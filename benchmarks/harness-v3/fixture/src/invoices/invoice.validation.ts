import { CreateInvoiceDto } from './dto/create-invoice.dto';

/** Returns a list of human-readable problems. Empty list means the body is fine. */
export function validateCreateInvoice(body: Partial<CreateInvoiceDto>): string[] {
  const errors: string[] = [];

  if (typeof body.number !== 'string' || body.number.length < 3 || body.number.length > 32) {
    errors.push('number must be a string of 3..32 characters');
  }
  if (!Number.isInteger(body.amountCents) || Number(body.amountCents) <= 0) {
    errors.push('amountCents must be a positive integer');
  }
  if (!Number.isInteger(body.customerId) || Number(body.customerId) <= 0) {
    errors.push('customerId must be a positive integer');
  }
  if (body.currency !== undefined && typeof body.currency !== 'string') {
    errors.push('currency must be a string');
  }

  return errors;
}
