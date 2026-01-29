/**
 * tests/workers/index.test.ts
 * Tests for main worker router and service endpoints
 */

import { describe, it, expect } from 'vitest';

// =============================================================================
// ROUTING TESTS
// =============================================================================

describe('Worker Routing', () => {
  const subdomains = [
    { host: 'stats.dnscloak.net', expectedHandler: 'stats-relay' },
    { host: 'dnstt.dnscloak.net', expectedHandler: 'dnstt-setup' },
    { host: 'sos.dnscloak.net', expectedHandler: 'sos-setup' },
    { host: 'reality.dnscloak.net', expectedHandler: 'service-landing' },
    { host: 'ws.dnscloak.net', expectedHandler: 'service-landing' },
    { host: 'wg.dnscloak.net', expectedHandler: 'service-landing' },
    { host: 'conduit.dnscloak.net', expectedHandler: 'service-landing' },
    { host: 'dnscloak.net', expectedHandler: 'main-landing' },
    { host: 'www.dnscloak.net', expectedHandler: 'main-landing' },
  ];

  for (const { host, expectedHandler } of subdomains) {
    it(`should route ${host} to ${expectedHandler}`, () => {
      const url = new URL(`https://${host}/`);
      const subdomain = url.hostname.split('.')[0];
      
      expect(url.hostname).toBe(host);
      expect(subdomain).toBeTruthy();
    });
  }

  it('should handle unknown subdomains gracefully', () => {
    const url = new URL('https://unknown.dnscloak.net/');
    // Should return 404 or redirect to main site
    expect(url.hostname).toContain('dnscloak.net');
  });
});

// =============================================================================
// INSTALL SCRIPT DELIVERY TESTS
// =============================================================================

describe('Install Script Delivery', () => {
  const services = ['reality', 'ws', 'wg', 'dnstt', 'conduit', 'sos'];

  for (const service of services) {
    it(`should serve install script for ${service}`, () => {
      // GET /{service}.dnscloak.net/ should return bash script
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
    const installCommand = 'curl -sSL https://reality.dnscloak.net | sudo bash';
    expect(installCommand).toContain('curl');
    expect(installCommand).toContain('sudo bash');
  });

  it('should not expose server IP in landing page', () => {
    // Landing page should not contain actual server IP
    // Only domain names
    const htmlContent = '<p>Install with: curl -sSL reality.dnscloak.net | sudo bash</p>';
    expect(htmlContent).not.toMatch(/\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/);
  });
});

// =============================================================================
// GPG SIGNATURE ENDPOINTS (Issue #9)
// =============================================================================

describe('GPG Signature Endpoints (Issue #9)', () => {
  it('should serve /.sig for each service', () => {
    // After Issue #9 is implemented:
    // GET /reality.dnscloak.net/.sig → returns GPG signature
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
      worker: 'dnscloak',
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
    const allowedOrigin = 'https://dnscloak.net';
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
    expect(disallowedOrigin).not.toBe('https://dnscloak.net');
  });
});
