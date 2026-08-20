import { Controller, Get, Param, ParseIntPipe, Query } from '@nestjs/common';
import { AuditService } from './audit.service';

@Controller('audit')
export class AuditController {
  constructor(private readonly audit: AuditService) {}

  @Get()
  list(@Query() query: { page?: string; limit?: string }) {
    return this.audit.list(query);
  }

  @Get('summary/:customerId')
  summary(@Param('customerId', ParseIntPipe) customerId: number) {
    return this.audit.summary(customerId);
  }
}
