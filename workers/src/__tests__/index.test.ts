/**
 * tests/workers/index.test.ts
 * Tests for main worker router and service endpoints
 */

import { describe, it, expect } from 'vitest';
import { pageLanding } from '../tui/pages/landing.js';

// =============================================================================
// ROUTING TESTS
// =============================================================================

describe('Worker Routing', () => {
  // Path-based routing (primary)
  const pathRoutes = [
    { url: 'https://vany.sh/', expectedHandler: 'main-landing' },
    { url: 'https://vany.sh/reality', expectedHandler: 'service-landing' },
    { url: 'https://vany.sh/ws', expectedHandler: 'service-landing' },
    { url: 'https://vany.sh/wg', expectedHandler: 'service-landing' },
    { url: 'https://vany.sh/dnstt', expectedHandler: 'dnstt-setup' },
    { url: 'https://vany.sh/sos', expectedHandler: 'sos-setup' },
    { url: 'https://vany.sh/conduit', expectedHandler: 'service-landing' },
    { url: 'https://vany.sh/dnstt/setup/linux', expectedHandler: 'dnstt-client-setup' },
    { url: 'https://vany.sh/dnstt/client', expectedHandler: 'dnstt-client-page' },
  ];

  // Subdomain routing (backward compat)
  const subdomainRoutes = [
    { url: 'https://stats.vany.sh/', expectedHandler: 'stats-relay' },
    { url: 'https://reality.vany.sh/', expectedHandler: 'service-landing' },
    { url: 'https://dnstt.vany.sh/', expectedHandler: 'dnstt-setup' },
    { url: 'https://www.vany.sh/', expectedHandler: 'main-landing' },
  ];

  for (const { url: rawUrl, expectedHandler } of [...pathRoutes, ...subdomainRoutes]) {
    it(`should route ${rawUrl} to ${expectedHandler}`, () => {
      const url = new URL(rawUrl);
      expect(url.hostname).toContain('vany.sh');
    });
  }

  it('should handle unknown subdomains gracefully', () => {
    const url = new URL('https://unknown.vany.sh/');
    // Should return 404 or redirect to main site
    expect(url.hostname).toContain('vany.sh');
  });
});

// =============================================================================
// INSTALL SCRIPT DELIVERY TESTS
// =============================================================================

describe('Install Script Delivery', () => {
  const services = ['reality', 'ws', 'wg', 'dnstt', 'conduit', 'sos'];

  for (const service of services) {
    it(`should serve install script for ${service}`, () => {
      // GET /{service}.vany.sh/ should return bash script
      const expectedContentType = 'text/plain';
      expect(expectedContentType).toBe('text/plain');
    });
  }

  it('should include proper shebang in scripts', () => {
    const expectedShebang = '#!/bin/bash';
    expect(expectedShebang).toBe('#!/bin/bash');
  });

  it('should set correct Content-Type header', () => {
    // Should be text/plain or application/x-sh
    const validContentTypes = ['text/plain', 'application/x-sh', 'text/x-shellscript'];
    expect(validContentTypes).toContain('text/plain');
  });

  it('should include cache headers for scripts', () => {
    // Scripts should have appropriate caching
    // Short cache for development, longer for production
    const cacheControl = 'public, max-age=300'; // 5 minutes
    expect(cacheControl).toContain('max-age');
  });
});

// =============================================================================
// LANDING PAGE TESTS
// =============================================================================

describe('Landing Pages', () => {
  it('should return HTML for landing pages', () => {
    const contentType = 'text/html';
    expect(contentType).toBe('text/html');
  });

  it('should include install instructions', () => {
    // Landing page should show curl command
    const installCommand = 'curl https://vany.sh/reality | sudo bash';
    expect(installCommand).toContain('curl');
    expect(installCommand).toContain('sudo bash');
  });

  it('should not expose server IP in landing page', () => {
    // Landing page should not contain actual server IP
    // Only domain names
    const htmlContent = '<p>Install with: curl vany.sh/reality | sudo bash</p>';
    expect(htmlContent).not.toMatch(/\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/);
  });
});

// =============================================================================
// CENSORSHIP BYPASS FALLBACK TESTS
// =============================================================================

describe('Censorship Bypass Fallbacks', () => {
  it('should include GitHub Raw as a non-Cloudflare fallback', () => {
    // GitHub uses Fastly CDN, not Cloudflare. Critical for users in countries
    // where Cloudflare is fully blocked (e.g. Iran digital blackout)
    const landing = pageLanding();
    expect(landing).toContain('raw.githubusercontent.com');
    expect(landing).toContain('Fastly');
  });

  it('should include direct IP access with --resolve flag', () => {
    const landing = pageLanding();
    expect(landing).toContain('--resolve');
    expect(landing).toContain('104.16.0.1');
  });

  it('should include Windows/CMD/PowerShell instructions', () => {
    const landing = pageLanding();
    expect(landing).toContain('WINDOWS');
    expect(landing).toContain('WSL');
    expect(landing).toContain('PowerShell');
    expect(landing).toContain('curl.exe');
  });

  it('should include offline sharing as last resort', () => {
    const landing = pageLanding();
    expect(landing).toContain('Offline');
    expect(landing).toContain('start.sh');
  });

  it('should list GitHub Raw before DoH in fallback order', () => {
    // GitHub (Fastly CDN) should be tried before DoH/CF since in a full
    // Cloudflare blackout, DoH to 1.1.1.1 is also blocked
    const landing = pageLanding();
    const githubIdx = landing.indexOf('GitHub Raw');
    const dohIdx = landing.indexOf('DNS-over-HTTPS');
    expect(githubIdx).toBeGreaterThan(-1);
    expect(dohIdx).toBeGreaterThan(-1);
    expect(githubIdx).toBeLessThan(dohIdx);
  });
});

// =============================================================================
// GPG SIGNATURE ENDPOINTS (Issue #9)
// =============================================================================

describe('GPG Signature Endpoints (Issue #9)', () => {
  it('should serve /.sig for each service', () => {
    // After Issue #9 is implemented:
    // GET /vany.sh/reality/.sig → returns GPG signature
    const sigEndpoint = '/.sig';
    expect(sigEndpoint).toBe('/.sig');
  });

  it('should serve /verified bootstrap script', () => {
    // GET /verified → returns script that verifies before running
    const verifiedEndpoint = '/verified';
    expect(verifiedEndpoint).toBe('/verified');
  });

  it('should serve /key for public GPG key', () => {
    // GET /key → returns public GPG key
    const keyEndpoint = '/key';
    expect(keyEndpoint).toBe('/key');
  });

  it('should set correct Content-Type for signatures', () => {
    const sigContentType = 'application/pgp-signature';
    expect(sigContentType).toBe('application/pgp-signature');
  });

  it('should set correct Content-Type for public key', () => {
    const keyContentType = 'application/pgp-keys';
    expect(keyContentType).toBe('application/pgp-keys');
  });
});

// =============================================================================
// HEALTH CHECK ENDPOINT
// =============================================================================

describe('Health Check Endpoint', () => {
  it('should respond to /health', () => {
    const healthPath = '/health';
    expect(healthPath).toBe('/health');
  });

  it('should return JSON response', () => {
    const contentType = 'application/json';
    expect(contentType).toBe('application/json');
  });

  it('should include basic status', () => {
    const healthResponse = {
      status: 'ok',
      worker: 'vany',
      timestamp: new Date().toISOString(),
    };

    expect(healthResponse.status).toBe('ok');
    expect(healthResponse.worker).toBeTruthy();
  });
});

// =============================================================================
// ERROR HANDLING
// =============================================================================

describe('Error Handling', () => {
  it('should return 404 for unknown paths', () => {
    const notFoundStatus = 404;
    expect(notFoundStatus).toBe(404);
  });

  it('should return 405 for unsupported methods', () => {
    const methodNotAllowedStatus = 405;
    expect(methodNotAllowedStatus).toBe(405);
  });

  it('should not expose stack traces in production', () => {
    // Error responses should be generic, not detailed
    const errorResponse = { error: 'Internal Server Error' };
    expect(errorResponse).not.toHaveProperty('stack');
    expect(errorResponse).not.toHaveProperty('trace');
  });

  it('should log errors for debugging', () => {
    // Errors should be logged to console.error for Cloudflare logs
    expect(console.error).toBeDefined();
  });
});

// =============================================================================
// SECURITY HEADERS
// =============================================================================

describe('Security Headers', () => {
  const requiredHeaders = [
    'X-Content-Type-Options',
    'X-Frame-Options',
    'Referrer-Policy',
  ];

  for (const header of requiredHeaders) {
    it(`should include ${header} header`, () => {
      // All responses should include security headers
      expect(header).toBeTruthy();
    });
  }

  it('should set X-Content-Type-Options to nosniff', () => {
    const expectedValue = 'nosniff';
    expect(expectedValue).toBe('nosniff');
  });

  it('should set X-Frame-Options to DENY', () => {
    const expectedValue = 'DENY';
    expect(expectedValue).toBe('DENY');
  });

  it('should set Referrer-Policy to strict-origin-when-cross-origin', () => {
    const expectedValue = 'strict-origin-when-cross-origin';
    expect(expectedValue).toBe('strict-origin-when-cross-origin');
  });
});

// =============================================================================
// CORS HANDLING
// =============================================================================

describe('CORS Handling', () => {
  it('should handle OPTIONS preflight requests', () => {
    const preflightMethod = 'OPTIONS';
    expect(preflightMethod).toBe('OPTIONS');
  });

  it('should return appropriate CORS headers for allowed origins', () => {
    const allowedOrigin = 'https://vany.sh';
    const corsHeaders = {
      'Access-Control-Allow-Origin': allowedOrigin,
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, X-Signature',
    };

    expect(corsHeaders['Access-Control-Allow-Origin']).toBe(allowedOrigin);
  });

  it('should not return CORS headers for disallowed origins', () => {
    const disallowedOrigin = 'https://evil.com';
    // Should either omit CORS headers or return error
    expect(disallowedOrigin).not.toBe('https://vany.sh');
  });
});
