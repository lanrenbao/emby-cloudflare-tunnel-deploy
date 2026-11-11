// ecosystem.config.js - pm2 process manager config
// Usage:
//   1. Edit EMBY_DIR / CLOUDFLARED_DIR / TUNNEL_ID / CRED_JSON / HOSTNAME below
//   2. pm2 start ecosystem.config.js && pm2 save
const EMBY_DIR = "D:\\EmbyServer";
const CLOUDFLARED_DIR = "C:\\ProgramData\\cloudflared";
const TUNNEL_ID = "<TUNNEL-ID>";
const CRED_JSON = "C:\\Users\\<you>\\.cloudflared\\" + TUNNEL_ID + ".json";
const HOSTNAME = "media.example.com";

module.exports = {
  apps: [
    {
      name: "emby-server",
      script: EMBY_DIR + "\\EmbyServer.exe",
      cwd: EMBY_DIR,
      max_restarts: 10,
      restart_delay: 5000
    },
    {
      name: "emby-tunnel",
      script: CLOUDFLARED_DIR + "\\cloudflared.exe",
      args: [
        "tunnel", "--config", CLOUDFLARED_DIR + "\\config.yml",
        "--protocol", "http2", "run", "emby"
      ],
      max_restarts: 10,
      restart_delay: 5000
    }
  ]
};

// config.yml must contain:
//   tunnel: <TUNNEL-ID>
//   credentials-file: <CRED_JSON>
//   ingress:
//     - hostname: <HOSTNAME>
//       service: http://127.0.0.1:8096
//     - service: http_status:404
