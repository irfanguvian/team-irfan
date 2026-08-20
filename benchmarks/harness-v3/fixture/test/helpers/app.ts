import { INestApplication } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { PrismaClient } from '@prisma/client';
import { AppModule } from '../../src/app.module';
import { PrismaService } from '../../src/prisma/prisma.service';
import { seed } from '../../prisma/seed';

export const API_KEY = process.env.API_KEY ?? 'bench-key';

export interface TestApp {
  app: INestApplication;
  prisma: PrismaService;
  close: () => Promise<void>;
}

/** Boots the real Nest app against the real SQLite file and reseeds it. */
export async function bootstrap(): Promise<TestApp> {
  const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
  const app = moduleRef.createNestApplication();
  await app.init();

  const prisma = app.get(PrismaService);
  await seed(prisma as unknown as PrismaClient);

  return { app, prisma, close: () => app.close() };
}
