import * as esbuild from 'esbuild';
import path from 'path';

// Add the phoenix dependencies as externals to simulate the default Phoenix setup
const phoenixExternals = ['phoenix', 'phoenix_html', 'phoenix_live_view', '../vendor/topbar'];

esbuild.build({
  entryPoints: ['js/app.js'],
  bundle: true,
  target: 'es2017',
  outdir: '../priv/static/assets',
  external: ['/fonts/*', '/images/*', ...phoenixExternals],
  platform: 'browser',
  format: 'iife',
  define: {
    global: 'window',
    process: 'process',
    Buffer: 'Buffer'
  },
  inject: ['./polyfills.js'],
  loader: {
    '.js': 'jsx',
  },
  resolveExtensions: ['.js', '.jsx'],
  nodePaths: [
    // Try to simulate NODE_PATH Phoenix uses for deps
    path.resolve('../deps'),
    'node_modules'
  ],
  alias: {
    // Add aliases for common Phoenix packages
    'phoenix': path.resolve('../deps/phoenix/priv/static/phoenix.js'),
    'phoenix_html': path.resolve('../deps/phoenix_html/priv/static/phoenix_html.js'),
    'phoenix_live_view': path.resolve('../deps/phoenix_live_view/priv/static/phoenix_live_view.js')
  }
}).catch(() => process.exit(1)); 