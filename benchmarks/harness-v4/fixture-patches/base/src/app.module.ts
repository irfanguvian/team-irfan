import { Module } from '@nestjs/common';
import { PrismaModule } from './prisma/prisma.module';
import { InvoicesModule } from './invoices/invoices.module';
import { ReportsModule } from './reports/reports.module';
import { CustomersModule } from './customers/customers.module';
import { RefundsModule } from './refunds/refunds.module';
import { AuditModule } from './audit/audit.module';

@Module({
  imports: [
    PrismaModule,
    InvoicesModule,
    ReportsModule,
    CustomersModule,
    RefundsModule,
    AuditModule,
  ],
})
export class AppModule {}
