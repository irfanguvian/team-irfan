import { Controller, Get, Param, ParseIntPipe, UseGuards } from '@nestjs/common';
import { ApiKeyGuard } from '../auth/api-key.guard';
import { ReportsService } from './reports.service';

@Controller('reports')
@UseGuards(ApiKeyGuard)
export class ReportsController {
  constructor(private readonly reports: ReportsService) {}

  @Get('daily/:customerId')
  daily(@Param('customerId', ParseIntPipe) customerId: number) {
    return this.reports.daily(customerId);
  }
}
