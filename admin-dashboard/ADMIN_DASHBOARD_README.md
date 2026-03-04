# VanTrade Admin Dashboard

A modern, real-time admin dashboard for monitoring VanTrade trading platform metrics including user analytics, token consumption, and trading performance.

## Features

✨ **Real-Time Updates** - Server-Sent Events (SSE) for live data streaming
📊 **Interactive Charts** - Beautiful Chart.js visualizations
🎨 **Dark Theme Design** - Professional glassmorphism UI with Material Design
🔐 **Admin Authentication** - JWT-based secure login
📈 **Comprehensive Metrics** - Users, tokens, profits, and activity tracking
⚡ **Fast & Responsive** - Angular 19 with standalone components

## Tech Stack

- **Frontend**: Angular 19 (standalone components)
- **UI Framework**: Angular Material 19
- **Charts**: Chart.js 4 + ng2-charts
- **Styling**: SCSS with modern glassmorphism effects
- **HTTP**: Angular HttpClient with custom interceptors
- **Real-Time**: EventSource API for Server-Sent Events

## Project Structure

```
admin-dashboard/
├── src/
│   ├── app/
│   │   ├── core/
│   │   │   ├── services/
│   │   │   │   ├── auth.service.ts           # JWT authentication
│   │   │   │   └── admin-api.service.ts      # API calls & SSE
│   │   │   ├── guards/
│   │   │   │   └── auth.guard.ts             # Route protection
│   │   │   └── interceptors/
│   │   │       └── token.interceptor.ts      # Auto-attach JWT
│   │   ├── features/
│   │   │   ├── login/
│   │   │   │   ├── login.component.ts
│   │   │   │   ├── login.component.html
│   │   │   │   └── login.component.scss
│   │   │   └── dashboard/
│   │   │       ├── dashboard.component.ts
│   │   │       ├── dashboard.component.html
│   │   │       └── dashboard.component.scss
│   │   ├── app.routes.ts                     # Routing config
│   │   ├── app.config.ts                     # App configuration
│   │   ├── app.component.ts
│   │   └── app.component.html
│   ├── main.ts
│   ├── styles.scss                           # Global styles + Material theme
│   └── index.html
├── angular.json                              # Angular CLI config
├── tsconfig.json
├── package.json
├── proxy.conf.json                           # Dev server proxy
└── ADMIN_DASHBOARD_README.md

```

## Installation

### Prerequisites
- Node.js 18+ and npm 9+
- FastAPI backend running on `http://localhost:8000`
- Admin user created in the database

### Setup

```bash
cd admin-dashboard

# Install dependencies
npm install

# (Optional) If you have peer dependency warnings, use:
# npm install --legacy-peer-deps
```

## Running the Application

### Development Server

```bash
npm start
# or
ng serve
```

Navigate to `http://localhost:4200` in your browser.

The app will automatically proxy API requests to `http://localhost:8000/api`.

### Build for Production

```bash
npm run build
# or
ng build --configuration production
```

Output will be in the `dist/` directory.

## API Integration

The dashboard connects to the FastAPI backend at:
- **Base URL**: `http://localhost:8000/api/v1/admin`

### Key Endpoints Used

```
POST   /api/v1/admin/auth/login              # Admin login
GET    /api/v1/admin/metrics/summary         # Overall metrics
GET    /api/v1/admin/metrics/users           # Per-user analytics
GET    /api/v1/admin/metrics/tokens          # Token usage over time
GET    /api/v1/admin/events                  # SSE real-time updates
```

## Dashboard Pages

### Login Page
- Clean, modern login interface
- Form validation
- Error handling with user-friendly messages
- Credential-based JWT authentication

### Admin Dashboard
- **Overview Cards**: 4 key metrics (Users, Tokens, Profit, Trades)
- **Live Indicator**: Shows real-time SSE connection status
- **Token Chart**: 30-day token usage visualization
- **Key Metrics**: Daily averages and totals
- **Users Table**: Recent users with analytics
- **Real-Time Updates**: Auto-refreshing metrics every 5 seconds

## Authentication

The dashboard uses JWT-based authentication:

1. Admin enters username/password on login page
2. Backend validates credentials and returns JWT token
3. Token is stored in `localStorage` and automatically attached to all requests
4. Token expires after 30 minutes (configurable)
5. Logout clears token and redirects to login page

## Styling & Theme

The dashboard features:
- **Dark Theme**: Background gradient `#0f1117` to `#1a1f2e`
- **Accent Color**: Purple-to-pink gradient (`#6c63ff` to `#ff6b9d`)
- **Glassmorphism**: Frosted glass effects with backdrop blur
- **Smooth Animations**: Entrance, hover, and transition effects
- **Responsive Design**: Grid-based layout that adapts to screen size

### Key Color Palette

```scss
$primary-dark: #0f1117;
$secondary-dark: #1a1f2e;
$accent-primary: #6c63ff;
$accent-secondary: #ff6b9d;
$text-primary: #e2e8f0;
$text-secondary: #a0aec0;
$success: #10b981;
$danger: #ef4444;
```

## Real-Time Updates (SSE)

The dashboard uses Server-Sent Events for live metric updates:

```typescript
// Subscribes to /api/v1/admin/events endpoint
subscribeToEvents(): Observable<SSEEvent> {
  return new Observable(observer => {
    const eventSource = new EventSource(`${this.apiUrl}/events?token=${token}`);
    eventSource.onmessage = (event) => {
      observer.next(JSON.parse(event.data));
    };
    // ... error handling
  });
}
```

The server pushes updates every 5 seconds with current metrics.

## Configuration

### Development Proxy
Edit `proxy.conf.json` to change the backend URL:

```json
{
  "/api": {
    "target": "http://your-backend-url",
    "secure": false,
    "changeOrigin": true
  }
}
```

### JWT Settings
Backend JWT settings (in `app/core/config.py`):
```python
ADMIN_JWT_SECRET = "your-secret-key"
ADMIN_JWT_ALGORITHM = "HS256"
ADMIN_JWT_EXPIRATION_MINUTES = 30
```

## Troubleshooting

### CORS Errors
Ensure the FastAPI backend has CORS enabled for `http://localhost:4200`:
```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # or specify ["http://localhost:4200"]
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

### SSE Connection Issues
- Check browser console for connection errors
- Verify backend is running on port 8000
- Ensure valid JWT token in localStorage
- Check that `/api/v1/admin/events` endpoint is accessible

### Login Failures
- Verify admin user exists in database
- Check password hash matches
- Ensure backend `/api/v1/admin/auth/login` endpoint is working
- Check browser Network tab for response details

## Performance Tips

- Charts are limited to 30-day history
- User table shows only first 10 recent users
- SSE updates throttled to every 5 seconds
- Metrics cached in memory between updates
- No periodic polling when SSE connection is active

## Security Notes

1. **JWT Token**: Stored in `localStorage` (consider secure cookies for production)
2. **HTTPS**: Use HTTPS in production
3. **CORS**: Configure allowed origins properly
4. **Token Rotation**: Implement refresh tokens for longer sessions
5. **XSS Protection**: Angular sanitizes content by default

## Browser Support

- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+

## Future Enhancements

- [ ] Admin user management page
- [ ] Custom date range for metrics
- [ ] Export reports as PDF/CSV
- [ ] Email notifications for alerts
- [ ] Advanced filtering and search
- [ ] Dark/Light theme toggle
- [ ] Mobile-optimized views
- [ ] Automated performance monitoring

## License

Part of the VanTrade Project - All Rights Reserved

## Support

For issues or questions, contact the development team or open an issue in the project repository.
