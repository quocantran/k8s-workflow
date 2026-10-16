import { Injectable, OnModuleInit } from '@nestjs/common';
import * as mysql from 'mysql2/promise';
import Redis from 'ioredis';

@Injectable()
export class AppService implements OnModuleInit {
  private dbPool: mysql.Pool;
  private redisClient: Redis;

  async onModuleInit() {
    // 1. Kết nối Percona MySQL (Đọc hoàn toàn từ ConfigMap/Secret)
    const dbHost = process.env.DB_HOST || 'mysql-external';
    const dbPort = parseInt(process.env.DB_PORT || '3306');
    const dbUser = process.env.DB_USER || 'movie_user';
    const dbPassword = process.env.DB_PASSWORD || '';
    const dbName = process.env.DB_NAME || 'movie_db';

    console.log(`[Backend] Đang kết nối MySQL tại ${dbHost}:${dbPort}/${dbName}...`);
    this.dbPool = mysql.createPool({
      host: dbHost,
      port: dbPort,
      user: dbUser,
      password: dbPassword,
      database: dbName,
      waitForConnections: true,
      connectionLimit: 10,
    });

    // 2. Kết nối Redis Service trong Kubernetes
    const redisHost = process.env.REDIS_HOST || 'redis-service';
    const redisPort = parseInt(process.env.REDIS_PORT || '6379');

    console.log(`[Backend] Đang kết nối Redis tại ${redisHost}:${redisPort}...`);
    this.redisClient = new Redis({
      host: redisHost,
      port: redisPort,
      retryStrategy: (times) => Math.min(times * 100, 3000),
      lazyConnect: true,
    });

    try {
      await this.redisClient.connect();
      console.log('[Backend] Kết nối Redis thành công!');
    } catch (err) {
      console.warn('[Backend] Cảnh báo: Chưa kết nối được Redis, app sẽ dùng fallback trực tiếp MySQL.');
    }
  }

  // API 1: Healthcheck kiểm tra kết nối DB và Redis
  async getHealth() {
    let dbStatus = 'disconnected';
    let redisStatus = 'disconnected';

    try {
      const [rows] = await this.dbPool.query('SELECT 1 AS ok');
      if (rows) dbStatus = 'connected (Percona MySQL)';
    } catch (err: any) {
      dbStatus = `error: ${err.message}`;
    }

    try {
      const ping = await this.redisClient.ping();
      if (ping === 'PONG') redisStatus = 'connected (In-Cluster Redis)';
    } catch (err: any) {
      redisStatus = `error: ${err.message}`;
    }

    return {
      status: 'ok',
      service: 'backend-service',
      pod: process.env.HOSTNAME || 'local',
      timestamp: new Date().toISOString(),
      db: dbStatus,
      redis: redisStatus,
    };
  }

  // API 2: Lấy danh sách phim (Ưu tiên đọc Redis Cache, miss thì truy vấn MySQL)
  async getMovies() {
    const cacheKey = 'movies:all';

    // Thử đọc từ Redis Cache
    try {
      if (this.redisClient && this.redisClient.status === 'ready') {
        const cached = await this.redisClient.get(cacheKey);
        if (cached) {
          return {
            source: 'redis_cache (In-Cluster)',
            data: JSON.parse(cached),
          };
        }
      }
    } catch (err) {
      console.error('[Redis Cache Miss/Error]', err);
    }

    // Truy vấn trực tiếp MySQL
    const [rows]: any = await this.dbPool.query(
      'SELECT id, title, genre, duration, total_seats, booked_seats, created_at FROM movies ORDER BY id ASC'
    );

    // Lưu vào Redis Cache 30 giây
    try {
      if (this.redisClient && this.redisClient.status === 'ready') {
        await this.redisClient.setex(cacheKey, 30, JSON.stringify(rows));
      }
    } catch (err) {
      console.error('[Redis Cache Set Error]', err);
    }

    return {
      source: 'mysql_percona (Host DB)',
      data: rows,
    };
  }

  // API 3: Đặt vé xem phim
  async bookTicket(movieId: number, customerName: string, seats: number) {
    if (!movieId || !customerName || seats <= 0) {
      return { success: false, message: 'Dữ liệu không hợp lệ!' };
    }

    const connection = await this.dbPool.getConnection();
    try {
      await connection.beginTransaction();

      // Lock dòng dữ liệu (SELECT FOR UPDATE)
      const [movieRows]: any = await connection.query(
        'SELECT id, title, total_seats, booked_seats FROM movies WHERE id = ? FOR UPDATE',
        [movieId]
      );

      if (!movieRows || movieRows.length === 0) {
        await connection.rollback();
        return { success: false, message: 'Không tìm thấy phim!' };
      }

      const movie = movieRows[0];
      const remaining = movie.total_seats - movie.booked_seats;

      if (remaining < seats) {
        await connection.rollback();
        return { success: false, message: `Phim chỉ còn ${remaining} chỗ khả dụng!` };
      }

      // Cập nhật số ghế đã đặt
      await connection.query(
        'UPDATE movies SET booked_seats = booked_seats + ? WHERE id = ?',
        [seats, movieId]
      );

      // Thêm bản ghi đặt vé
      const [bookingResult]: any = await connection.query(
        'INSERT INTO bookings (movie_id, customer_name, seats_count) VALUES (?, ?, ?)',
        [movieId, customerName, seats]
      );

      await connection.commit();

      // Xóa cache Redis để lần đọc tới cập nhật số ghế mới nhất
      try {
        if (this.redisClient && this.redisClient.status === 'ready') {
          await this.redisClient.del('movies:all');
        }
      } catch (e) {}

      return {
        success: true,
        bookingId: bookingResult.insertId,
        movieTitle: movie.title,
        bookedSeats: seats,
        remainingSeats: remaining - seats,
      };
    } catch (err: any) {
      await connection.rollback();
      return { success: false, message: err.message };
    } finally {
      connection.release();
    }
  }
}
