import { Injectable, HttpException, HttpStatus } from '@nestjs/common';
import axios from 'axios';

@Injectable()
export class GatewayService {
  private backendUrl = process.env.BACKEND_SERVICE_URL || 'http://backend-service:5000';

  async getHealth() {
    try {
      const res = await axios.get(`${this.backendUrl}/api/health`, { timeout: 3000 });
      return {
        status: 'ok',
        service: 'api-gateway',
        gatewayPod: process.env.HOSTNAME || 'local',
        backend: res.data,
      };
    } catch (err: any) {
      return {
        status: 'partial_ok',
        service: 'api-gateway',
        gatewayPod: process.env.HOSTNAME || 'local',
        backendStatus: 'unreachable',
        error: err.message,
      };
    }
  }

  async getMovies() {
    try {
      const res = await axios.get(`${this.backendUrl}/api/movies`, { timeout: 5000 });
      return res.data;
    } catch (err: any) {
      throw new HttpException(
        { message: 'Không thể kết nối đến Backend Service', error: err.message },
        HttpStatus.BAD_GATEWAY
      );
    }
  }

  async bookTicket(data: any) {
    try {
      const res = await axios.post(`${this.backendUrl}/api/book`, data, { timeout: 5000 });
      return res.data;
    } catch (err: any) {
      throw new HttpException(
        { message: 'Lỗi xử lý đặt vé tại Backend Service', error: err.message },
        HttpStatus.INTERNAL_SERVER_ERROR
      );
    }
  }
}
