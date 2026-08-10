import EmbeddedPostgres from 'embedded-postgres';
const pg = new EmbeddedPostgres({
  databaseDir: '/tmp/pgdata',
  user: 'postgres',
  password: 'postgres',
  port: 5433,
  persistent: true,
  // initialise is a no-op when the cluster already exists; only start.
});
await pg.start();
console.log('PG READY on 5433');
process.on('SIGTERM', async () => { try { await pg.stop(); } catch {} process.exit(0); });
process.on('SIGINT', async () => { try { await pg.stop(); } catch {} process.exit(0); });
