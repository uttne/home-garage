import { parseArgs } from 'node:util';
import { Buffer } from 'node:buffer';
import { defaultClusterPath, defaultRepoUrl } from '../config';
import { ensureNamespace, applyManifest } from '../lib/kubectl';
import { assertCommand, capture, printSection, run, fail } from '../lib/process';
import { renderTemplate } from '../lib/templates';

export function bootstrapInfisicalCredentialsCommand(args: string[]): void {
  const { values } = parseArgs({
    args,
    options: {
      'secret-namespace': { type: 'string' },
      'secret-name': { type: 'string' },
    },
    allowPositionals: false,
  });

  assertCommand('kubectl');

  const secretNamespace = values['secret-namespace'] ?? process.env.INFISICAL_CREDENTIALS_NAMESPACE ?? 'external-secrets';
  const secretName = values['secret-name'] ?? process.env.INFISICAL_CREDENTIALS_SECRET_NAME ?? 'infisical-universal-auth';
  const clientId = process.env.INFISICAL_CLIENT_ID?.trim() ?? '';
  const clientSecret = process.env.INFISICAL_CLIENT_SECRET?.trim() ?? '';

  if (!clientId && !clientSecret) {
    console.log('INFISICAL_CLIENT_ID / INFISICAL_CLIENT_SECRET are not set.');
    console.log('Skipping bootstrap of Infisical credentials.');
    return;
  }

  if (!clientId || !clientSecret) {
    fail('Both INFISICAL_CLIENT_ID and INFISICAL_CLIENT_SECRET must be set together.');
  }

  ensureNamespace(secretNamespace);

  const manifest = capture('kubectl', [
    'create',
    'secret',
    'generic',
    secretName,
    '--namespace',
    secretNamespace,
    `--from-literal=clientId=${clientId}`,
    `--from-literal=clientSecret=${clientSecret}`,
    '--dry-run=client',
    '-o',
    'yaml',
  ]);
  applyManifest(manifest);

  console.log(`Infisical credentials secret '${secretNamespace}/${secretName}' is ready.`);
}

export function setupCommand(args: string[]): void {
  const { values } = parseArgs({
    args,
    options: {
      'repo-url': { type: 'string' },
      'cluster-path': { type: 'string' },
    },
    allowPositionals: false,
  });

  const repoUrl = values['repo-url'] ?? defaultRepoUrl;
  const clusterPath = values['cluster-path'] ?? defaultClusterPath;

  assertCommand('kubectl');
  assertCommand('helm');

  printSection('Installing ArgoCD via Helm');
  ensureNamespace('argocd');
  run('helm', ['repo', 'add', 'argo', 'https://argoproj.github.io/argo-helm'], { allowFailure: true, quiet: true });
  run('helm', ['repo', 'update'], { quiet: true });
  run('helm', ['upgrade', '--install', 'argocd', 'argo/argo-cd', '--namespace', 'argocd', '--version', '9.3.7']);

  printSection('Waiting for ArgoCD Server');
  run('kubectl', ['rollout', 'status', 'deployment', 'argocd-server', '-n', 'argocd', '--timeout=120s']);

  printSection('Bootstrapping Infisical credentials');
  bootstrapInfisicalCredentialsCommand([]);

  printSection('Applying Root App');
  const manifest = renderTemplate('root-app.template.yaml', {
    repoUrl,
    clusterPath,
  });
  applyManifest(manifest);

  printSection('Initial Admin Password');
  const passwordBase64 = capture('kubectl', ['-n', 'argocd', 'get', 'secret', 'argocd-initial-admin-secret', '-o', 'jsonpath={.data.password}']);
  const password = Buffer.from(passwordBase64, 'base64').toString('utf8');
  console.log(password);
  console.log(`Bootstrap completed. ArgoCD is now syncing ${clusterPath} from ${repoUrl}.`);
}
