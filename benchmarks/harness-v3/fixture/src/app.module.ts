import { Module } from '@nestjs/common';
import { PrismaModule } from './prisma/prisma.module';
import { InvoicesModule } from './invoices/invoices.module';
import { ReportsModule } from './reports/reports.module';

@Module({
  imports: [PrismaModule, InvoicesModule, ReportsModule],
})
export class AppModule {}
