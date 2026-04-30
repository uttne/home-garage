import { randomBytes } from 'node:crypto';

export function randomSecret(length = 32): string {
  return randomBytes(length).toString('base64url');
}
