#!/usr/bin/env node

const { execSync } = require('child_process');

try {
  console.log('Building assets with custom esbuild config...');
  execSync('node esbuild.config.mjs', { stdio: 'inherit' });
  console.log('Assets built successfully!');
} catch (error) {
  console.error('Error building assets:', error);
  process.exit(1);
} 