import { Controller, Get, Param, ParseIntPipe, Query, UseGuards } from '@nestjs/common';
import { ApiKeyGuard } from '../auth/api-key.guard';
import { CustomersService } from './customers.service';

@Controller('customers')
@UseGuards(ApiKeyGuard)
export class CustomersController {
  constructor(private readonly customers: CustomersService) {}

  @Get()
  list(@Query() query: { page?: string; limit?: string }) {
    return this.customers.list(query);
  }

  @Get(':id/activity')
  activity(@Param('id', ParseIntPipe) id: number) {
    return this.customers.activity(id);
  }
}
