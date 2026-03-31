# Web UI & Dashboard

Frontend interface for Privacy Guardian management and monitoring.

## Files

- **index.html** — Main dashboard HTML
- **app.js** — Frontend logic (React/Vanilla JS)
- **styles.css** — UI styling
- **config.js** — Settings & constants
- **data/runtime.json** — Runtime metrics & status

## Features

- Real-time device monitoring
- DNS query statistics
- Whitelist/blacklist management
- System status
- Settings configuration

## Access

Once deployed, open in your browser:

```
http://192.168.4.1:3000
```

(Or use the IP/port specified in your `.env`)

## Development

For local development:

```bash
# Start local server (if applicable)
npm start

# Build for production
npm run build
```

This UI is also available through AdGuard Home's built-in dashboard.
