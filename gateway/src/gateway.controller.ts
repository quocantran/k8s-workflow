import { Controller, Get, Post, Body } from '@nestjs/common';
import { GatewayService } from './gateway.service';

@Controller('api')
export class GatewayController {
  constructor(private readonly gatewayService: GatewayService) {}

  @Get('health')
  getHealth() {
    return this.gatewayService.getHealth();
  }

  @Get('movies')
  getMovies() {
    return this.gatewayService.getMovies();
  }

  @Post('book')
  bookTicket(@Body() body: any) {
    return this.gatewayService.bookTicket(body);
  }
}
