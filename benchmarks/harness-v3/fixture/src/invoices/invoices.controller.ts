import { Body, Controller, Get, HttpCode, Post, Query, UseGuards } from '@nestjs/common';
import { ApiKeyGuard } from '../auth/api-key.guard';
import { InvoicesService } from './invoices.service';
import { CreateInvoiceDto } from './dto/create-invoice.dto';
import { validateCreateInvoice } from './invoice.validation';

@Controller('invoices')
@UseGuards(ApiKeyGuard)
export class InvoicesController {
  constructor(private readonly invoices: InvoicesService) {}

  @Get()
  list(@Query() query: { page?: string; limit?: string }) {
    return this.invoices.list(query);
  }

  @Post()
  @HttpCode(200)
  async create(@Body() body: CreateInvoiceDto) {
    const errors = validateCreateInvoice(body);
    if (errors.length > 0) {
      return { ok: false, errors };
    }
    return this.invoices.create(body);
  }
}
