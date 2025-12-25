# OptiLab Frontend

A modern, minimalistic frontend for the OptiLab Smart Lab Resource Monitoring System, built with React, TypeScript, Vite, and Tailwind CSS.

## 🎨 Design Philosophy

Inspired by TensorFlow's clean and professional design, this frontend features:

- **Minimalistic & Clean**: Focus on content with subtle animations
- **Modern UI Components**: Card-based layouts with smooth transitions
- **Responsive Design**: Works seamlessly on desktop, tablet, and mobile
- **Performance First**: Built with Vite for lightning-fast development and production builds
- **Type-Safe**: Full TypeScript support for robust development

## 🚀 Features

- **Dashboard**: Real-time overview of all systems with key metrics
- **Systems**: Detailed view of all monitored lab computers
- **Analytics**: Advanced insights and optimization recommendations
- **Alerts**: Real-time alert management and notifications

## 🛠️ Tech Stack

- **React 18** - UI library
- **TypeScript** - Type safety
- **Vite** - Build tool and dev server
- **Tailwind CSS** - Utility-first styling
- **React Router** - Client-side routing
- **Axios** - HTTP client
- **Lucide React** - Beautiful icons

## 📦 Installation

```bash
cd frontend
npm install
```

## 🏃‍♂️ Development

Start the development server:

```bash
npm run dev
```

The application will be available at `http://localhost:5173`

## 🔧 Configuration

### Environment Variables

Create a `.env` file in the frontend directory:

```env
VITE_API_URL=http://localhost:8000
```

### API Proxy

The Vite dev server is configured to proxy API requests to the backend:

```typescript
// vite.config.ts
server: {
  proxy: {
    '/api': {
      target: 'http://localhost:8000',
      changeOrigin: true,
    }
  }
}
```

## 🏗️ Build

Build for production:

```bash
npm run build
```

Preview production build:

```bash
npm run preview
```

## 📁 Project Structure

```
src/
├── components/       # Reusable UI components
│   ├── Navbar.tsx
│   ├── Hero.tsx
│   └── Dashboard.tsx
├── pages/           # Page components
│   ├── Systems.tsx
│   ├── Analytics.tsx
│   └── Alerts.tsx
├── lib/             # Utilities and API client
│   └── api.ts
├── App.tsx          # Main app component
├── main.tsx         # Entry point
└── style.css        # Global styles and Tailwind
```

## 🎯 Key Components

### Dashboard
- System statistics overview
- Resource utilization charts
- Recent alerts
- Top resource consumers

### Systems
- Grid view of all monitored systems
- Real-time status indicators
- CPU and memory usage bars
- Search and filter functionality

### Analytics
- Utilization trends
- Department distribution
- Top consumers analysis
- Optimization recommendations

### Alerts
- Active alert management
- Alert severity classification
- Recent activity timeline
- Alert statistics

## 🎨 Color Palette

Primary colors inspired by TensorFlow:

```css
primary: {
  50: '#fef7ee',
  100: '#fdecd3',
  200: '#fad6a5',
  300: '#f7b96d',
  400: '#f39232',
  500: '#f07316',  /* Main brand color */
  600: '#e1560b',
  700: '#bb3d0b',
  800: '#953110',
  900: '#792a10',
}
```

## 📱 Responsive Breakpoints

- **Mobile**: < 768px
- **Tablet**: 768px - 1024px
- **Desktop**: > 1024px

## 🔗 API Integration

The frontend integrates with the backend API endpoints:

- `GET /api/systems` - List all systems
- `GET /api/systems/status` - System status summary
- `GET /api/systems/{id}/metrics` - System metrics history
- `GET /api/analytics/top-consumers/{type}` - Top resource consumers
- `GET /api/analytics/underutilized` - Underutilized systems
- `GET /api/alerts/active` - Active alerts

## 🚧 Future Enhancements

- [ ] Real-time WebSocket updates
- [ ] Interactive charts with Chart.js or Recharts
- [ ] Dark mode support
- [ ] Advanced filtering and sorting
- [ ] Export data functionality
- [ ] User authentication
- [ ] Notification system
- [ ] Mobile app

## 📄 License

MIT License - See LICENSE file for details

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
