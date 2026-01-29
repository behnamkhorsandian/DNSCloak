import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // Test environment
    environment: 'node',
    
    // Include test files
    include: [
      'src/**/*.test.ts',
      'src/__tests__/**/*.ts',
    ],
    
    // Exclude
    exclude: [
      'node_modules',
      'dist',
    ],
    
    // Coverage
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      include: ['src/**/*.ts'],
      exclude: ['src/**/*.test.ts', 'src/__tests__/**'],
    },
    
    // Reporters
    reporters: ['verbose'],
    
    // Globals (describe, it, expect without imports)
    globals: true,
    
    // Timeout
    testTimeout: 10000,
    
    // Watch mode disabled in CI
    watch: false,
  },
});
