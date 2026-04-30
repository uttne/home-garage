import { spawnSync } from 'node:child_process';

export type RunOptions = {
  cwd?: string;
  input?: string;
  allowFailure?: boolean;
  quiet?: boolean;
};

export type RunResult = {
  stdout: string;
  stderr: string;
  status: number;
};

export function fail(message: string): never {
  throw new Error(message);
}

export function printSection(title: string): void {
  console.log('');
  console.log(`=== ${title} ===`);
}

export function run(command: string, args: string[], options: RunOptions = {}): RunResult {
  const result = spawnSync(command, args, {
    cwd: options.cwd,
    input: options.input,
    encoding: 'utf8',
    stdio: ['pipe', 'pipe', 'pipe'],
  });

  if (result.error) {
    if ((result.error as NodeJS.ErrnoException).code === 'ENOENT') {
      fail(`Required command '${command}' was not found.`);
    }

    throw result.error;
  }

  const stdout = result.stdout ?? '';
  const stderr = result.stderr ?? '';
  const status = result.status ?? 0;

  if (!options.quiet) {
    if (stdout.length > 0) {
      process.stdout.write(stdout);
    }
    if (stderr.length > 0) {
      process.stderr.write(stderr);
    }
  }

  if (status !== 0 && !options.allowFailure) {
    fail(`Command failed: ${command} ${args.join(' ')}`);
  }

  return { stdout, stderr, status };
}

export function capture(command: string, args: string[], options: Omit<RunOptions, 'quiet'> = {}): string {
  return run(command, args, { ...options, quiet: true }).stdout.trim();
}

export function assertCommand(command: string): void {
  const result = spawnSync(command, ['--help'], {
    encoding: 'utf8',
    stdio: 'ignore',
  });

  if (result.error && (result.error as NodeJS.ErrnoException).code === 'ENOENT') {
    fail(`Required command '${command}' was not found.`);
  }
}
