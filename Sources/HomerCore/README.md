# HomerCore

The API (requests, SSE), the per-instance cookie jar, instance endpoints, `HomerClient`, and the models and formats several modules share.

## Design notes

- **Cookies are kept per instance, not by `URLSession`** (`HomerCookieJar`): `HTTPCookieStorage` matches cookies by host only — ports are ignored, and Homer's cookie has `Path=/` — so two instances on one host (`localhost:8080` and `:8081`, or two sub-paths) would sign each other out there. The session's `URLSession` neither stores nor sends cookies; `HomerAPI.send` adds the instance's jar as the `Cookie` header and feeds every `Set-Cookie` back (an already-expired one, as logout sends, removes). The jars persist to `homerSessions.json` in Application Support with `0600` permissions, so sessions survive a relaunch — the same trade `HTTPCookieStorage.shared` makes with its own file
- **One `URLSession` per instance** (`HomerAPI.session(for:)`): instances behind one Kubernetes ingress (`*.okubefs1.kube.lsoffice.cz`) share its IP and wildcard certificate, so a single session coalesces their HTTP/2 connections and sends one instance's requests over another's connection — the ingress answers those 421 Misdirected Request. Sessions never share connections
- Every request carries `X-Homer-CSRF: 1`: the backend's CSRF guard rejects cookie-authenticated requests without it (Homer ADR-0016)
