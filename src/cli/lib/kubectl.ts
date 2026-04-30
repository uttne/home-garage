import { capture, run } from './process';

export function applyManifest(manifest: string): void {
  run('kubectl', ['apply', '-f', '-'], { input: manifest });
}

export function ensureNamespace(namespace: string): void {
  const manifest = capture('kubectl', ['create', 'namespace', namespace, '--dry-run=client', '-o', 'yaml']);
  applyManifest(manifest);
}
