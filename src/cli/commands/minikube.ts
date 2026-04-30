import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { copyWorkingTree } from '../lib/filesystem';
import { ensureNamespace, applyManifest } from '../lib/kubectl';
import { assertCommand, capture, fail, run } from '../lib/process';
import { randomSecret } from '../lib/random';
import { renderTemplate } from '../lib/templates';
import { setupCommand } from './setup';

type PublishOptions = {
  namespace: string;
  name: string;
  repoRoot: string;
};

type SeedOptions = {
  namespace: string;
  postgresAdminUser: string;
  postgresAppUser: string;
  postgresAdminPassword?: string;
  postgresAppPassword?: string;
  n8nEncryptionKey?: string;
};

export function publishLocalRepoMinikubeCommand(args: string[]): string {
  const { values } = parseArgs({
    args,
    options: {
      namespace: { type: 'string' },
      name: { type: 'string' },
      'repo-root': { type: 'string' },
    },
    allowPositionals: false,
  });

  const options: PublishOptions = {
    namespace: values.namespace ?? 'argocd',
    name: values.name ?? 'home-garage-git',
    repoRoot: resolve(values['repo-root'] ?? process.cwd()),
  };

  assertCommand('kubectl');
  assertCommand('git');

  ensureNamespace(options.namespace);
  const manifest = renderTemplate('minikube-git-daemon.template.yaml', {
    name: options.name,
    namespace: options.namespace,
  });
  applyManifest(manifest);
  run('kubectl', ['rollout', 'status', `deployment/${options.name}`, '-n', options.namespace, '--timeout=120s'], { quiet: true });

  const podName = capture('kubectl', [
    'get',
    'pod',
    '-n',
    options.namespace,
    '-l',
    `app=${options.name}`,
    '--field-selector=status.phase=Running',
    '-o',
    'jsonpath={.items[0].metadata.name}',
  ]);
  if (!podName) {
    fail('Unable to locate the local git daemon pod.');
  }

  run('kubectl', ['exec', '-n', options.namespace, podName, '--', 'sh', '-c', 'rm -rf /srv/git/home-garage'], {
    quiet: true,
    allowFailure: true,
  });

  const bundleDirectory = mkdtempSync(join(tmpdir(), 'home-garage-bundle-'));
  const snapshotDirectory = mkdtempSync(join(tmpdir(), 'home-garage-snapshot-'));
  const workingTreeDirectory = join(snapshotDirectory, 'repo');
  const bundlePath = join(bundleDirectory, 'home-garage.bundle');

  try {
    copyWorkingTree(options.repoRoot, workingTreeDirectory);

    run('git', ['init', '-b', 'main'], { cwd: workingTreeDirectory, quiet: true });
    run('git', ['config', 'user.name', 'Copilot'], { cwd: workingTreeDirectory, quiet: true });
    run('git', ['config', 'user.email', 'copilot@example.com'], { cwd: workingTreeDirectory, quiet: true });
    run('git', ['add', '.'], { cwd: workingTreeDirectory, quiet: true });
    run('git', ['commit', '-m', 'minikube snapshot'], { cwd: workingTreeDirectory, quiet: true });
    run('git', ['bundle', 'create', bundlePath, '--all'], { cwd: workingTreeDirectory, quiet: true });

    run('kubectl', ['cp', 'home-garage.bundle', `${options.namespace}/${podName}:/tmp/home-garage.bundle`], {
      cwd: bundleDirectory,
      quiet: true,
    });
  } finally {
    rmSync(snapshotDirectory, { recursive: true, force: true });
    rmSync(bundleDirectory, { recursive: true, force: true });
  }

  run('kubectl', [
    'exec',
    '-n',
    options.namespace,
    podName,
    '--',
    'sh',
    '-c',
    'rm -rf /srv/git/home-garage && git clone --bare /tmp/home-garage.bundle /srv/git/home-garage && rm -f /tmp/home-garage.bundle',
  ]);

  const repoUrl = `git://${options.name}.${options.namespace}.svc.cluster.local/home-garage`;
  let reachable = false;
  for (let attempt = 0; attempt < 20; attempt += 1) {
    const result = run(
      'kubectl',
      ['run', 'git-check', '--rm', '-i', '--restart=Never', '--image=alpine/git', '--command', '--', 'git', 'ls-remote', repoUrl],
      { quiet: true, allowFailure: true },
    );

    if (result.status === 0) {
      reachable = true;
      break;
    }
  }

  if (!reachable) {
    fail('The in-cluster git service did not become reachable from minikube.');
  }

  console.log(`Local git repository is available at ${repoUrl}`);
  return repoUrl;
}

export function seedMinikubeSecretsCommand(args: string[]): void {
  const { values } = parseArgs({
    args,
    options: {
      namespace: { type: 'string' },
      'postgres-admin-user': { type: 'string' },
      'postgres-app-user': { type: 'string' },
      'postgres-admin-password': { type: 'string' },
      'postgres-app-password': { type: 'string' },
      'n8n-encryption-key': { type: 'string' },
    },
    allowPositionals: false,
  });

  const options: SeedOptions = {
    namespace: values.namespace ?? 'external-secrets',
    postgresAdminUser: values['postgres-admin-user'] ?? 'postgres',
    postgresAppUser: values['postgres-app-user'] ?? 'n8n',
    postgresAdminPassword: values['postgres-admin-password'],
    postgresAppPassword: values['postgres-app-password'],
    n8nEncryptionKey: values['n8n-encryption-key'],
  };

  assertCommand('kubectl');

  const postgresAdminPassword = options.postgresAdminPassword ?? randomSecret();
  const postgresAppPassword = options.postgresAppPassword ?? randomSecret();
  const n8nEncryptionKey = options.n8nEncryptionKey ?? randomSecret();

  ensureNamespace(options.namespace);

  const secrets = [
    {
      name: 'home-garage-n8n-encryption-key',
      data: [`--from-literal=N8N_ENCRYPTION_KEY=${n8nEncryptionKey}`],
    },
    {
      name: 'home-garage-n8n-postgres-user',
      data: [`--from-literal=POSTGRES_USER=${options.postgresAdminUser}`],
    },
    {
      name: 'home-garage-n8n-postgres-password',
      data: [`--from-literal=POSTGRES_PASSWORD=${postgresAdminPassword}`],
    },
    {
      name: 'home-garage-n8n-postgres-non-root-user',
      data: [`--from-literal=POSTGRES_NON_ROOT_USER=${options.postgresAppUser}`],
    },
    {
      name: 'home-garage-n8n-postgres-non-root-password',
      data: [`--from-literal=POSTGRES_NON_ROOT_PASSWORD=${postgresAppPassword}`],
    },
  ];

  for (const secret of secrets) {
    const manifest = capture('kubectl', [
      'create',
      'secret',
      'generic',
      secret.name,
      '--namespace',
      options.namespace,
      ...secret.data,
      '--dry-run=client',
      '-o',
      'yaml',
    ]);
    applyManifest(manifest);
  }

  console.log(`Seeded minikube secret source data in namespace '${options.namespace}'.`);
}

export function setupMinikubeCommand(args: string[]): void {
  const { values } = parseArgs({
    args,
    options: {
      namespace: { type: 'string' },
      name: { type: 'string' },
      'repo-root': { type: 'string' },
      'secret-namespace': { type: 'string' },
      'postgres-admin-user': { type: 'string' },
      'postgres-app-user': { type: 'string' },
      'postgres-admin-password': { type: 'string' },
      'postgres-app-password': { type: 'string' },
      'n8n-encryption-key': { type: 'string' },
    },
    allowPositionals: false,
  });

  const repoUrl = publishLocalRepoMinikubeCommand([
    '--namespace',
    values.namespace ?? 'argocd',
    '--name',
    values.name ?? 'home-garage-git',
    '--repo-root',
    values['repo-root'] ?? process.cwd(),
  ]);

  setupCommand(['--repo-url', repoUrl, '--cluster-path', 'clusters/minikube']);

  const seedArgs = [
    '--namespace',
    values['secret-namespace'] ?? 'external-secrets',
    '--postgres-admin-user',
    values['postgres-admin-user'] ?? 'postgres',
    '--postgres-app-user',
    values['postgres-app-user'] ?? 'n8n',
  ];
  if (values['postgres-admin-password']) {
    seedArgs.push('--postgres-admin-password', values['postgres-admin-password']);
  }
  if (values['postgres-app-password']) {
    seedArgs.push('--postgres-app-password', values['postgres-app-password']);
  }
  if (values['n8n-encryption-key']) {
    seedArgs.push('--n8n-encryption-key', values['n8n-encryption-key']);
  }

  seedMinikubeSecretsCommand(seedArgs);
}
