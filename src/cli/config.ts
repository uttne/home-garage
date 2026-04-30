export const defaultRepoUrl = 'https://github.com/uttne/home-garage.git';
export const defaultClusterPath = 'clusters/home';

export const requiredNamespaces = [
  'argocd',
  'external-secrets',
  'istio-system',
  'home-garage-observability',
  'n8n',
];

export const requiredApplications = [
  'platform-core',
  'platform-networking',
  'platform-observability-metrics',
  'platform-observability-logging',
  'platform-observability-tracing',
  'apps',
  'argocd',
  'external-secrets-operator',
  'istio-base',
  'istiod',
  'victoria-metrics-k8s-stack',
  'grafana',
  'loki',
  'fluent-bit',
  'tempo',
  'otel-collector',
];
