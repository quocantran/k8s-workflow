import { Controller, Get, Post, Body } from '@nestjs/common';
import { AppService } from './app.service';

@Controller('api')
export class AppController {
  constructor(private readonly appService: AppService) {}

  @Get('health')
  getHealth() {
    return this.appService.getHealth();
  }

  @Get('movies')
  getMovies() {
    return this.appService.getMovies();
  }

  @Post('book')
  bookTicket(@Body() body: { movieId: number; customerName: string; seats: number }) {
    return this.appService.bookTicket(body.movieId, body.customerName, body.seats);
  }
}
