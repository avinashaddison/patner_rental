// ============================================================================
// Companion Ranchi — pm2 process manager config (VPS deployment)
// ----------------------------------------------------------------------------
// Usage on the server:
//   cd /opt/companion-ranchi/backend && npm ci && npx prisma generate \
//     && npx prisma migrate deploy && npm run seed
//   pm2 start /opt/companion-ranchi/deploy/ecosystem.config.js
//   pm2 save && pm2 startup systemd   # run the printed command to persist on boot
//
// NOTE on clustering: with instances > 1 the Socket.IO Redis adapter is REQUIRED
// so a message published on one worker reaches sockets on another. Provision Redis
// and set REDIS_URL before scaling out. For a single small instance, set
// instances: 1 and you can omit Redis.
// ============================================================================

const BACKEND_DIR = '/opt/companion-ranchi/backend';

module.exports = {
  apps: [
    {
      name: 'companion-backend',
      cwd: BACKEND_DIR,
      // Run via npm so the package's "start" script is the single source of truth
      // for the entrypoint (e.g. node src/server.js). Avoids drift if the path changes.
      script: 'npm',
      args: 'start',
      instances: 1, // set to 'max' for cluster mode AFTER configuring the Socket.IO Redis adapter
      exec_mode: 'fork', // switch to 'cluster' together with instances: 'max'
      max_memory_restart: '512M',
      autorestart: true,
      // Back off restarts if the process crashes on boot (e.g. bad env) instead of looping fast.
      min_uptime: '10s',
      max_restarts: 10,
      restart_delay: 4000,
      env: {
        NODE_ENV: 'production',
        // All other variables come from backend/.env (loaded by the app's config layer).
      },
      // Logs (ensure /var/log/companion exists and is writable by the deploy user).
      out_file: '/var/log/companion/backend-out.log',
      error_file: '/var/log/companion/backend-err.log',
      merge_logs: true,
      time: true,
    },
  ],
};
