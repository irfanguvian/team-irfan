import { Controller, Get, Query, UseGuards } from '@nestjs/common';
import { ApiKeyGuard } from '../auth/api-key.guard';
import { RefundsService } from './refunds.service';

@Controller('refunds')
@UseGuards(ApiKeyGuard)
export class RefundsController {
  constructor(private readonly refunds: RefundsService) {}

  @Get()
  list(@Query() query: { page?: string; limit?: string }) {
    return this.refunds.list(query);
  }
}
