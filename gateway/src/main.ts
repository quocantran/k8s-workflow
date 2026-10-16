import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';

async function bootstrap() {
  const app = await NestFactory.create(AppModule);
  app.enableCors();
  const port = process.env.PORT || 8080;
  await app.listen(port);
  console.log(`🚀 [API Gateway] Đang lắng nghe tại cổng: ${port}`);
}
bootstrap();
