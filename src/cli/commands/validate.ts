import { requiredApplications, requiredNamespaces } from '../config';
import { assertCommand, printSection, run } from '../lib/process';

export function validateCommand(): void {
  assertCommand('kubectl');

  printSection('Namespaces');
  for (const namespace of requiredNamespaces) {
    const result = run('kubectl', ['get', 'namespace', namespace, '-o', 'jsonpath={.metadata.name}'], {
      quiet: true,
      allowFailure: true,
    });
    console.log(result.status === 0 && result.stdout.trim() === namespace ? `OK   namespace/${namespace}` : `MISS namespace/${namespace}`);
  }

  printSection('ArgoCD Applications');
  const applicationRows = run('kubectl', ['get', 'applications.argoproj.io', '-n', 'argocd', '--no-headers'], {
    quiet: true,
    allowFailure: true,
  });
  if (applicationRows.status !== 0 || !applicationRows.stdout.trim()) {
    console.log('No ArgoCD applications were found.');
  } else {
    process.stdout.write(applicationRows.stdout);
  }

  for (const application of requiredApplications) {
    const syncStatus = run(
      'kubectl',
      ['get', 'applications.argoproj.io', application, '-n', 'argocd', '-o', 'jsonpath={.status.sync.status}'],
      { quiet: true, allowFailure: true },
    );
    const healthStatus = run(
      'kubectl',
      ['get', 'applications.argoproj.io', application, '-n', 'argocd', '-o', 'jsonpath={.status.health.status}'],
      { quiet: true, allowFailure: true },
    );

    if (syncStatus.status === 0 && healthStatus.status === 0) {
      console.log(`APP  ${application} sync=${syncStatus.stdout.trim()} health=${healthStatus.stdout.trim()}`);
    } else {
      console.log(`APP  ${application} missing`);
    }
  }

  printSection('External Secrets');
  run('kubectl', ['get', 'clustersecretstore', 'platform-secrets', '-o', 'wide'], { allowFailure: true });
  run('kubectl', ['get', 'externalsecret', '-A'], { allowFailure: true });

  printSection('Core Deployments');
  run('kubectl', ['get', 'deploy', '-n', 'external-secrets'], { allowFailure: true });
  run('kubectl', ['get', 'deploy', '-n', 'istio-system'], { allowFailure: true });
  run('kubectl', ['get', 'pods', '-n', 'home-garage-observability'], { allowFailure: true });
  run('kubectl', ['get', 'pods', '-n', 'n8n'], { allowFailure: true });

  printSection('Suggested manual checks');
  console.log('1. kubectl describe clustersecretstore platform-secrets');
  console.log('2. kubectl get secret -n n8n postgres-secret n8n-secret');
  console.log('3. Open Grafana and confirm VictoriaMetrics, Loki, Tempo datasources are healthy.');
  console.log('4. Confirm the n8n pod has an istio-proxy sidecar and postgres does not.');
  console.log('5. Trigger application traffic and verify logs expose trace_id, then open the trace in Grafana.');
}
