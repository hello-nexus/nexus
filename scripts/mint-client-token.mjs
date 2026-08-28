#!/usr/bin/env node
// Mints the build credential a published Nexus client carries. Release CI runs
// this; it is also how the long-lived `dev` token for a lab machine is made.
//
//   NEXUS_CLIENT_SIGNING_KEY=<base64 pkcs8 ed25519> \
//     node scripts/mint-client-token.mjs --version 2.4.1 --channel stable --platform win-x64
//
// Generate the keypair once (private stays in the CI secret store, public in
// the API's NEXUS_CLIENT_PUBKEY):
//
//   node scripts/mint-client-token.mjs --keygen
//
// The token is verified by signature, so shipping a release needs no backend
// registration. It is extractable from any binary we publish and is a gate,
// not an authorization.
import { createPrivateKey, generateKeyPairSync, sign } from 'node:crypto';

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

if (process.argv.includes('--keygen')) {
  const { publicKey, privateKey } = generateKeyPairSync('ed25519');
  console.log('NEXUS_CLIENT_SIGNING_KEY (CI secret, private):');
  console.log(privateKey.export({ type: 'pkcs8', format: 'der' }).toString('base64'));
  console.log();
  console.log('NEXUS_CLIENT_PUBKEY (nexus-api env, public):');
  console.log(publicKey.export({ type: 'spki', format: 'der' }).toString('base64'));
  process.exit(0);
}

const raw = process.env.NEXUS_CLIENT_SIGNING_KEY;
if (!raw) {
  console.error('NEXUS_CLIENT_SIGNING_KEY is required');
  process.exit(1);
}

const key = createPrivateKey({
  key: Buffer.from(raw, 'base64'),
  format: 'der',
  type: 'pkcs8',
});

const payload = {
  v: arg('version', '0.0.0'),
  ch: arg('channel', 'stable'),
  p: arg('platform', 'unknown'),
  iat: Math.floor(Date.now() / 1000),
};

const body = Buffer.from(JSON.stringify(payload), 'utf8');
process.stdout.write(`${body.toString('base64url')}.${sign(null, body, key).toString('base64url')}`);
