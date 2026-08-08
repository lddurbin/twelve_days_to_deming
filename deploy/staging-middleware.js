// Vercel Edge Middleware for the persistent staging site (#536).
//
// Vercel's built-in SSO deployment protection only gates a project's
// per-deployment hash URLs (e.g. *-l8r4bagos-*.vercel.app) — confirmed live
// while building this — it does NOT apply to a project's aliased Production
// Domain, which is exactly the stable URL a persistent staging site needs.
// So access control is hand-rolled here instead: plain HTTP Basic Auth,
// checked against STAGING_BASIC_AUTH_USER/PASS project environment
// variables (set directly on the Vercel project, never passed through CI).
//
// Deployed via the Build Output API v3 (no `vercel build` step — see
// .github/workflows/deploy.yml's `staging` job), so this file is copied
// as-is into .vercel/output/functions/middleware.func/index.js. It must
// stay dependency-free: there is no bundling step to resolve an import.
export default function middleware(request) {
  const expectedUser = process.env.STAGING_BASIC_AUTH_USER;
  const expectedPass = process.env.STAGING_BASIC_AUTH_PASS;

  const authHeader = request.headers.get("authorization") || "";
  const [scheme, encoded] = authHeader.split(" ");
  if (scheme === "Basic" && encoded) {
    const decoded = atob(encoded);
    const separatorIndex = decoded.indexOf(":");
    const user = decoded.slice(0, separatorIndex);
    const pass = decoded.slice(separatorIndex + 1);
    if (user === expectedUser && pass === expectedPass) {
      // The Build Output API's wire signal for "continue routing" — lets
      // the noindex header route and static filesystem lookup still run.
      return new Response(null, { headers: { "x-middleware-next": "1" } });
    }
  }

  return new Response("Authentication required", {
    status: 401,
    headers: { "WWW-Authenticate": 'Basic realm="Staging"' },
  });
}
