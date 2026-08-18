import { CanActivate, ExecutionContext, Injectable, UnauthorizedException } from '@nestjs/common';

@Injectable()
export class ApiKeyGuard implements CanActivate {
  canActivate(context: ExecutionContext): boolean {
    const req = context.switchToHttp().getRequest();
    const key = req.headers['x-api-key'];
    if (!key || key !== (process.env.API_KEY ?? 'bench-key')) {
      throw new UnauthorizedException('invalid api key');
    }
    return true;
  }
}
