/**
 * LevelIt TLS 终结器。
 * 在 8443 上提供 HTTPS，把请求原样转发到本机已有的 levelit-proxy（127.0.0.1:80）。
 * TLS 在此终结，转发段是 localhost 明文（不出网，安全）。
 *
 * 这样不必改动现有 proxy；现有全部路由（auth/pk/social/leaderboard/AI）保持不变。
 *
 * 证书由 acme.sh（DuckDNS DNS-01）签发到 TLS_CERT/TLS_KEY，续期后会 reload 本服务。
 */
import https from "node:https";
import http from "node:http";
import fs from "node:fs";

const PORT          = Number(process.env.TLS_PORT) || 8443;
const UPSTREAM_PORT = Number(process.env.UPSTREAM_PORT) || 80;
const CERT = process.env.TLS_CERT || "/etc/levelit/tls/fullchain.pem";
const KEY  = process.env.TLS_KEY  || "/etc/levelit/tls/privkey.pem";

const options = {
  cert: fs.readFileSync(CERT),
  key:  fs.readFileSync(KEY),
};

const server = https.createServer(options, (req, res) => {
  const proxyReq = http.request(
    {
      hostname: "127.0.0.1",
      port: UPSTREAM_PORT,
      path: req.url,
      method: req.method,
      headers: req.headers,
    },
    (proxyRes) => {
      res.writeHead(proxyRes.statusCode, proxyRes.headers);
      proxyRes.pipe(res, { end: true });
    }
  );
  proxyReq.on("error", () => {
    res.writeHead(502, { "content-type": "application/json" });
    res.end(JSON.stringify({ error: "upstream unavailable" }));
  });
  req.pipe(proxyReq, { end: true });
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`levelit-tls listening on :${PORT} -> 127.0.0.1:${UPSTREAM_PORT}`);
});
