import { IsInt, IsOptional, IsPositive, IsString, Length } from 'class-validator';

export class CreateInvoiceDto {
  @IsString()
  @Length(3, 32)
  number: string;

  @IsInt()
  @IsPositive()
  amountCents: number;

  @IsInt()
  @IsPositive()
  customerId: number;

  @IsOptional()
  @IsString()
  currency?: string;
}
