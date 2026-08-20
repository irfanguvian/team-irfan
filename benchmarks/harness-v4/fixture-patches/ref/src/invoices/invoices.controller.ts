import { BadRequestException, Body, Controller, Get, Post, Query, UseGuards } from '@nestjs/common';
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
  async create(@Body() body: CreateInvoiceDto) {
    const errors = validateCreateInvoice(body);
    if (errors.length > 0) {
      throw new BadRequestException(errors);
    }
    return this.invoices.create(body);
  }
}
