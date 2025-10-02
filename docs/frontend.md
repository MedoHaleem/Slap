# Frontend Components

This document provides a comprehensive overview of the frontend components in the Slap application, including JavaScript hooks, CSS components, and LiveView templates.

## Table of Contents

1. [JavaScript Hooks](./frontend/javascript-hooks.md)
2. [CSS Components](./frontend/css.md)
3. [LiveView Templates](./frontend/templates.md)

## Overview

The Slap application uses Phoenix LiveView for server-side rendering with minimal client-side JavaScript. The frontend consists of:

- **JavaScript Hooks**: Client-side interactivity for specific UI elements
- **CSS Components**: Styled components built with Tailwind CSS
- **LiveView Templates**: HEEx templates for server-rendered HTML

## Technology Stack

- **Tailwind CSS**: Utility-first CSS framework
- **ESBuild**: JavaScript bundler
- **Phoenix LiveView**: Server-side rendering with real-time updates
- **JavaScript Hooks**: Client-side interactivity where needed

## Asset Pipeline

### JavaScript Bundling

JavaScript files are bundled with ESBuild:

```javascript
// assets/build.js
const esbuild = require('esbuild');

esbuild.build({
  entryPoints: ['js/app.js'],
  bundle: true,
  target: 'es2017',
  outfile: '../priv/static/assets/app.js',
  banner: {
    js: '// <%= phoenix_banner %>',
  },
}).catch(() => process.exit(1));
```

### CSS Processing

Tailwind CSS is processed and purged for production:

```javascript
// assets/tailwind.config.js
module.exports = {
  content: [
    './js/**/*.js',
    '../lib/slap_web/**/*.*ex',
    '../lib/slap_web/**/*.*heex'
  ],
  theme: {
    extend: {},
  },
  plugins: [],
}
```

## Frontend Architecture

### Component Structure

The frontend follows a component-based architecture:

```
assets/
├── js/
│   ├── app.js                 # Main JavaScript entry point
│   ├── components/            # Reusable JavaScript components
│   │   └── VoiceChat.js       # Voice chat component
│   ├── hooks/                 # Phoenix LiveView hooks
│   │   ├── ChatMessageTextArea.js
│   │   ├── RoomMessages.js
│   │   ├── Thread.js
│   │   └── voice_chat.js
│   └── utils/                 # Utility functions
│       └── messageHighlight.js
├── css/
│   └── app.css                # Main CSS file
└── package.json               # Node.js dependencies
```

### Integration with LiveView

JavaScript integrates with LiveView through:

1. **Hooks**: For client-side interactivity
2. **Events**: For client-to-server communication
3. **Push Events**: For server-to-client communication
4. **JS Commands**: For DOM manipulation

## Performance Considerations

### Asset Optimization

- CSS purging removes unused styles
- JavaScript minification reduces file size
- Asset fingerprinting enables caching
- CDN delivery for static assets

### JavaScript Minimization

Minimal JavaScript is used to:

- Reduce bundle size
- Improve page load times
- Simplify maintenance
- Enhance security

### CSS Optimization

Tailwind CSS optimization includes:

- Purging unused utilities
- Minifying CSS in production
- Critical CSS inlining (future)
- CSS compression

## Browser Compatibility

### Supported Browsers

- Chrome 90+
- Firefox 88+
- Safari 14+
- Edge 90+

### Progressive Enhancement

The application uses progressive enhancement:

- Core functionality works without JavaScript
- Enhanced experience with JavaScript enabled
- Graceful degradation for older browsers

## Security Considerations

### Content Security Policy

Content Security Policy headers are configured:

```elixir
# lib/slap_web/endpoint.ex
plug :put_secure_browser_headers,
  content_security_policy: "
    default-src 'self';
    script-src 'self' 'unsafe-eval';
    style-src 'self' 'unsafe-inline';
    img-src 'self' data:;
    connect-src 'self' wss:;
    font-src 'self';
  "
```

### XSS Prevention

XSS is prevented through:

- Proper HTML escaping in templates
- Sanitization of user input
- Secure DOM manipulation
- CSP header enforcement

## Development Workflow

### Asset Development

During development:

```bash
# Watch for changes and rebuild assets
npm run dev

# Or start Phoenix server (which includes asset watching)
mix phx.server
```

### Production Build

For production deployment:

```bash
# Build optimized assets
mix assets.deploy

# Or manually
npm run build
mix phx.digest
```

### Hot Module Replacement

Hot module replacement is available during development:

```javascript
// Live reload configuration
if (window.location.hostname === "localhost") {
  import("./live_socket").then((liveSocket) => {
    liveSocket.connect();
  });
}
```

## Frontend Testing

### JavaScript Testing

JavaScript can be tested with:

- Jest for unit tests
- Cypress for end-to-end tests
- Playwright for browser automation

### CSS Testing

CSS can be tested with:

- Visual regression testing
- Screenshot testing
- Component testing

## Accessibility

### WCAG Compliance

The application aims for WCAG 2.1 AA compliance:

- Semantic HTML structure
- Keyboard navigation support
- Screen reader compatibility
- Color contrast requirements

### Accessibility Features

Key accessibility features include:

- ARIA labels and roles
- Focus management
- Skip navigation links
- Alt text for images

## Future Enhancements

### Planned Improvements

- Component library documentation
- Design system implementation
- Storybook integration
- Advanced CSS animations

### Technical Improvements

- TypeScript migration (optional)
- Web Workers for heavy operations
- Service Worker implementation
- PWA capabilities

This frontend documentation provides an overview of the client-side components that enhance the user experience while maintaining the simplicity and performance of the Phoenix LiveView architecture.