const API_BASE = '/api';

const moviesContainer = document.getElementById('movies-container');
const systemStatusText = document.getElementById('system-status-text');
const diagSource = document.getElementById('diag-source');
const diagRedis = document.getElementById('diag-redis');
const diagDb = document.getElementById('diag-db');
const diagTime = document.getElementById('diag-time');
const btnRefresh = document.getElementById('btn-refresh');

const modal = document.getElementById('booking-modal');
const modalCloseBtn = document.getElementById('modal-close-btn');
const bookingForm = document.getElementById('booking-form');
const modalMovieTitle = document.getElementById('modal-movie-title');
const modalMovieId = document.getElementById('modal-movie-id');
const modalRemainingSeats = document.getElementById('modal-remaining-seats');
const btnConfirmBook = document.getElementById('btn-confirm-book');

// Fetch Health Status
async function checkHealth() {
  try {
    const res = await fetch(`${API_BASE}/health`);
    const data = await res.json();
    if (data.status === 'ok') {
      systemStatusText.textContent = `Online (K8s: ${data.service || 'Gateway'})`;
      diagRedis.textContent = data.redis || 'Connected';
      diagDb.textContent = data.db || 'Percona Connected';
      diagRedis.style.color = '#10b981';
      diagDb.style.color = '#10b981';
    }
  } catch (err) {
    systemStatusText.textContent = 'Mất kết nối Gateway';
    document.querySelector('.status-indicator').className = 'status-indicator error';
    diagRedis.textContent = 'Unavailable';
    diagDb.textContent = 'Unavailable';
  }
}

// Fetch Movies
async function loadMovies() {
  const startTime = performance.now();
  moviesContainer.innerHTML = `
    <div class="loading-state">
      <div class="spinner"></div>
      <p>Đang tải danh sách phim từ Backend...</p>
    </div>
  `;

  try {
    const res = await fetch(`${API_BASE}/movies`);
    const result = await res.json();
    const duration = Math.round(performance.now() - startTime);

    diagTime.textContent = `${duration} ms`;
    diagSource.textContent = result.source || 'MySQL';
    diagSource.style.color = result.source?.includes('redis') ? '#06b6d4' : '#fbbf24';

    renderMovies(result.data || []);
  } catch (err) {
    moviesContainer.innerHTML = `
      <div class="loading-state">
        <p style="color: #ef4444;">❌ Không thể kết nối tới Backend Service: ${err.message}</p>
      </div>
    `;
  }
}

function renderMovies(movies) {
  if (!movies || movies.length === 0) {
    moviesContainer.innerHTML = '<div class="loading-state"><p>Chưa có phim nào trong database.</p></div>';
    return;
  }

  moviesContainer.innerHTML = movies.map(movie => {
    const remaining = movie.total_seats - movie.booked_seats;
    const percent = Math.min(100, Math.round((movie.booked_seats / movie.total_seats) * 100));

    return `
      <div class="movie-card">
        <div>
          <span class="movie-badge">${movie.genre}</span>
          <h3 class="movie-title">${movie.title}</h3>
          <div class="movie-meta">
            <span>⏱️ ${movie.duration} phút</span>
            <span>🎟️ Tổng ${movie.total_seats} ghế</span>
          </div>

          <div class="seats-status">
            <div class="seats-bar-wrapper">
              <div class="seats-bar" style="width: ${percent}%;"></div>
            </div>
            <div class="seats-info">
              <span>Đã đặt: <strong>${movie.booked_seats}</strong> (${percent}%)</span>
              <span>Còn lại: <strong style="color: ${remaining > 0 ? '#10b981' : '#ef4444'}">${remaining}</strong></span>
            </div>
          </div>
        </div>

        <button 
          class="btn btn-primary btn-block" 
          onclick="openBookingModal(${movie.id}, '${movie.title}', ${remaining})"
          ${remaining <= 0 ? 'disabled' : ''}>
          ${remaining > 0 ? '🎟️ Đặt Vé Ngay' : 'Hết Vé'}
        </button>
      </div>
    `;
  }).join('');
}

window.openBookingModal = function(id, title, remaining) {
  modalMovieId.value = id;
  modalMovieTitle.textContent = `Đặt Vé: ${title}`;
  modalRemainingSeats.textContent = `${remaining} chỗ`;
  modal.classList.add('active');
};

modalCloseBtn.addEventListener('click', () => modal.classList.remove('active'));
modal.addEventListener('click', (e) => {
  if (e.target === modal) modal.classList.remove('active');
});

// Book Form Submit
bookingForm.addEventListener('submit', async (e) => {
  e.preventDefault();
  btnConfirmBook.disabled = true;
  btnConfirmBook.textContent = 'Đang xử lý đặt vé...';

  const movieId = parseInt(modalMovieId.value);
  const customerName = document.getElementById('customer-name').value;
  const seats = parseInt(document.getElementById('seat-count').value);

  try {
    const res = await fetch(`${API_BASE}/book`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ movieId, customerName, seats })
    });

    const data = await res.json();
    if (res.ok && data.success) {
      showToast(`🎉 Đặt thành công ${seats} vé cho ${customerName}!`, 'success');
      modal.classList.remove('active');
      bookingForm.reset();
      loadMovies();
    } else {
      showToast(`❌ Thất bại: ${data.message || 'Lỗi không xác định'}`, 'error');
    }
  } catch (err) {
    showToast(`❌ Lỗi mạng: ${err.message}`, 'error');
  } finally {
    btnConfirmBook.disabled = false;
    btnConfirmBook.textContent = 'Xác Nhận Đặt Vé';
  }
});

btnRefresh.addEventListener('click', () => {
  showToast('Đang làm mới dữ liệu từ cụm K8s...', 'success');
  loadMovies();
  checkHealth();
});

function showToast(message, type = 'success') {
  const container = document.getElementById('toast-container');
  const toast = document.createElement('div');
  toast.className = `toast ${type}`;
  toast.textContent = message;
  container.appendChild(toast);
  setTimeout(() => toast.remove(), 4000);
}

// Initial Run
checkHealth();
loadMovies();
