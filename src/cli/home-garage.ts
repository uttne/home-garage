import { bootstrapInfisicalCredentialsCommand, setupCommand } from './commands/setup';
import {
  publishLocalRepoMinikubeCommand,
  seedMinikubeSecretsCommand,
  setupMinikubeCommand,
} from './commands/minikube';
import { renderClusterSecretStoreCommand } from './commands/render-cluster-secret-store';
import { validateCommand } from './commands/validate';
import { fail } from './lib/process';

function usage(): string {
  return [
    'Usage: pnpm run home-garage -- <command> [options]',
    '',
    'Commands:',
    '  setup',
    '  setup-minikube',
    '  publish-local-repo-minikube',
    '  seed-minikube-secrets',
    '  bootstrap-infisical-credentials',
    '  validate',
    '  render-cluster-secret-store',
  ].join('\n');
}

function main(): void {
  const rawArgs = process.argv.slice(2);
  const normalizedArgs = rawArgs[0] === '--' ? rawArgs.slice(1) : rawArgs;
  const [command, ...args] = normalizedArgs;

  if (!command || command === 'help' || command === '--help') {
    console.log(usage());
    return;
  }

  switch (command) {
    case 'setup':
      setupCommand(args);
      return;
    case 'setup-minikube':
      setupMinikubeCommand(args);
      return;
    case 'publish-local-repo-minikube':
      publishLocalRepoMinikubeCommand(args);
      return;
    case 'seed-minikube-secrets':
      seedMinikubeSecretsCommand(args);
      return;
    case 'bootstrap-infisical-credentials':
      bootstrapInfisicalCredentialsCommand(args);
      return;
    case 'validate':
      validateCommand();
      return;
    case 'render-cluster-secret-store':
      renderClusterSecretStoreCommand(args);
      return;
    default:
      fail(`Unknown command '${command}'.\n\n${usage()}`);
  }
}

try {
  main();
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  console.error(message);
  process.exit(1);
}
