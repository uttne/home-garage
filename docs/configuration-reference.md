# home-garage 構成リファレンス

このドキュメントは、基盤の設計方針、repo の責務分離、sync wave、secret 設計、主要ファイルの役割をまとめた参照資料です。  
実際の構築や検証の手順は `docs\operations-guide.md` を参照してください。

## 1. アーキテクチャ方針

- Kubernetes: `k3s`
- GitOps: `ArgoCD`
- Secret 管理: `External Secrets Operator`
  - 初期 backend: `Infisical`
  - 将来移行先: `GCP Secret Manager`
- Service Mesh / Trace: `Istio` + `OpenTelemetry Collector` + `Tempo`
- Metrics: `VictoriaMetrics`
- Logs: `Loki` + `Fluent Bit`
- Visualization: `Grafana`
- Public exposure: `Cloudflare Tunnel`

## 2. リポジトリ構成

```text
bootstrap\   静的 manifest など bootstrap 補助ファイル
clusters\    cluster ごとの root 構成と overlay
platform\    共通プラットフォーム層
apps\        家庭内アプリケーション層
docs\        運用手順と構成リファレンス
src\         共通の Node.js + TypeScript CLI
system\      旧構成（移行元として保持）
manifests\   旧アプリ manifest（移行元として保持）
```

## 3. 共通 CLI

スクリプトの実装は `src\cli\` 配下に分割しています。  
エントリポイントは `src\cli\home-garage.ts`、実処理は `commands\` と `lib\`、YAML テンプレートは `templates\` に整理し、OS ごとの処理差分は持たず Node.js から `kubectl` / `helm` / `git` を呼ぶシンプルな構成です。

### 主なコマンド

- `pnpm run home-garage -- setup`
- `pnpm run home-garage -- setup-minikube`
- `pnpm run home-garage -- publish-local-repo-minikube`
- `pnpm run home-garage -- seed-minikube-secrets`
- `pnpm run home-garage -- bootstrap-infisical-credentials`
- `pnpm run home-garage -- validate`
- `pnpm run home-garage -- render-cluster-secret-store`

## 4. デプロイモデル

### 4.1 展開の流れ

1. `pnpm run home-garage -- setup` で ArgoCD を導入する
2. `root-app` が `clusters\home` または `clusters\minikube` を同期する
3. `clusters\base` 配下の App-of-Apps が `platform\` と `apps\` を sync wave 順に展開する
4. `platform\core` が ArgoCD、External Secrets Operator、`ClusterSecretStore` を整える
5. `platform\networking` が Istio を導入する
6. `platform\observability\*` が metrics / logging / tracing を導入する
7. `apps\*` が PostgreSQL と n8n を展開する

### 4.2 sync wave

- wave 0: `platform-core`
- wave 1: `platform-networking`
- wave 2: `platform-observability-metrics`
- wave 3: `platform-observability-logging`
- wave 4: `platform-observability-tracing`
- wave 5: `apps`

## 5. Secret 設計

アプリ側は `ExternalSecret` を共通表現とし、provider 差分は `ClusterSecretStore` に閉じ込めます。

### 5.1 代表的な secret key

- `home-garage-n8n-postgres-user`
- `home-garage-n8n-postgres-password`
- `home-garage-n8n-postgres-non-root-user`
- `home-garage-n8n-postgres-non-root-password`
- `home-garage-n8n-encryption-key`

### 5.2 provider 差し替え

- `platform\core\cluster-secret-store.yaml`
  - 実クラスタ向けの Infisical 用 `ClusterSecretStore`
- `platform\core\minikube\cluster-secret-store.yaml`
  - minikube 向けの Kubernetes provider 版 `ClusterSecretStore`
- `platform\core\cluster-secret-store-gcpsm.example`
  - 将来 GCP Secret Manager に切り替える場合の参考定義

差し替え用 manifest を生成する場合は、以下を使います。

```powershell
pnpm run home-garage -- render-cluster-secret-store --provider infisical --output-path .\platform\core\cluster-secret-store.yaml
```

```powershell
pnpm run home-garage -- render-cluster-secret-store --provider gcp-secret-manager --gcp-project-id your-gcp-project-id --output-path .\platform\core\cluster-secret-store.yaml
```

## 6. 主要ファイルリファレンス

### `src\cli\home-garage.ts`

- CLI のエントリポイントとコマンド dispatch を担当する
- 実処理は各 command module に委譲し、自身は薄いルーターに留めている

### `src\cli\commands\*.ts`

- `setup.ts`、`minikube.ts`、`validate.ts`、`render-cluster-secret-store.ts` に責務ごとに分割している
- bootstrap、minikube 補助、検証、manifest 生成をそれぞれ独立して追いやすくした

### `src\cli\lib\*.ts`

- 外部コマンド実行、Kubernetes apply、テンプレート描画、作業ツリー複製、乱数生成のような共通処理をまとめている
- command 層から重複ロジックを外し、関心ごとを分離している

### `src\cli\templates\*.template.yaml`

- 動的生成していた manifest を YAML テンプレートとして分離したもの
- `Handlebars` でプレースホルダだけ置き換えるため、YAML として読みやすく、エディタ補完も効きやすい

### `bootstrap\root-app.yaml`

- 静的な root app の雛形
- 実際の bootstrap では CLI が動的 manifest を生成するが、構造の参照点として repo に残している

### `clusters\base\kustomization.yaml`

- cluster 共通の App-of-Apps を束ねる親 Kustomization
- `apps.yaml`
- `platform-core.yaml`
- `platform-networking.yaml`
- `platform-observability-metrics.yaml`
- `platform-observability-logging.yaml`
- `platform-observability-tracing.yaml`
  を読み込む

### `clusters\home\kustomization.yaml`

- 実クラスタ向け overlay
- `repoURL=https://github.com/uttne/home-garage.git` を全 Application に流し込む
- path は base をそのまま使うため、`platform\core` と `apps` の標準構成が有効になる

### `clusters\minikube\kustomization.yaml`

- minikube 検証向け overlay
- repo URL を `git://home-garage-git.argocd.svc.cluster.local/home-garage` に差し替える
- `platform-core` の path を `platform\core\minikube` に差し替える
- `apps` の path を `apps\minikube` に差し替える
- production 向けの大枠は維持しつつ、secret source と app secret 解決方法だけを minikube 用に変える

### `platform\core\argocd.yaml`

- ArgoCD 自身を Helm chart `argo-cd` `9.3.7` で管理する child Application
- `argocd.home-garage.local` の Ingress を持つ
- Ingress health の custom script を持ち、address 未設定でも rules があれば Healthy とみなせる

### `platform\core\external-secrets-operator.yaml`

- External Secrets Operator を Helm chart `external-secrets` `2.0.1` で管理する child Application
- CRD の導入、ServiceMonitor の有効化を行う
- `ServerSideApply=true` と `Replace=true` を有効化している

### `platform\core\cluster-secret-store.yaml`

- production / home クラスタ向けの `ClusterSecretStore`
- Infisical provider を使い、アプリ側 `ExternalSecret` から共通参照される

### `platform\core\minikube\cluster-secret-store.yaml`

- minikube 用の `ClusterSecretStore`
- Infisical ではなく ESO の Kubernetes provider を使う
- `seed-minikube-secrets` が作った値を、各 `ExternalSecret` がここ経由で参照する

### `platform\networking\istiod.yaml`

- Istio control plane を Helm chart `istiod` `1.29.0` で導入する child Application
- access log を JSON 化し、`trace_id` をログに含める
- `meshConfig.extensionProviders` で OTel Collector を tracing backend として登録する

### `platform\observability\metrics\grafana.yaml`

- Grafana `10.5.15` を導入する child Application
- VictoriaMetrics / Loki / Tempo を最初から datasource として接続する
- minikube では volume 権限問題を避けるため `initChownData.enabled=false` を使う

### `platform\observability\metrics\victoriametrics.yaml`

- `victoria-metrics-k8s-stack` `0.72.4` を導入する child Application
- Grafana / Alertmanager / vmalert は無効化し、メトリクス収集に専念させる

### `platform\observability\logging\loki.yaml`

- Loki `6.53.0` を single-binary で導入する child Application
- filesystem backend + TSDB schema を明示し、chart の必須要件を満たす

### `platform\observability\logging\fluent-bit.yaml`

- Fluent Bit `0.56.0` を導入する child Application
- Node 上の `/var/log/containers/*.log` を tail し、Loki に転送する

### `platform\observability\tracing\tempo.yaml`

- Tempo `1.24.4` を導入する child Application
- OTLP receiver を有効化し、trace を保持する

### `platform\observability\tracing\otel-collector.yaml`

- OpenTelemetry Collector `0.146.1` を導入する child Application
- OTLP gRPC / HTTP receiver を公開し、Tempo へ export する

### `apps\postgres\configmap.yaml`

- PostgreSQL 起動後に `n8n` 用ロールと DB を整える初期化スクリプトを持つ
- 既存 volume に対しても安全に再実行できる

### `apps\postgres\statefulset.yaml`

- PostgreSQL 本体の StatefulSet
- `sidecar.istio.io/inject: "false"` により DB には sidecar を入れない

### `apps\n8n\externalsecret.yaml`

- n8n の encryption key を `n8n-secret` として同期する
- n8n の内部暗号化と資格情報保護に必要

### `apps\n8n\deployment.yaml`

- n8n 本体 Deployment
- PostgreSQL 待ちの init container を持つ
- `WEBHOOK_URL=http://my-home-n8n.local/` を現在の既定値として持つ
- 公開経路の TLS は Cloudflare Tunnel 側で扱う前提

### `apps\n8n\ingress.yaml`

- `my-home-n8n.local` を n8n にルーティングする Ingress
- Ingress 自体では TLS Secret を持たず、クラスター内では HTTP を前提にしている

### `apps\minikube\kustomization.yaml`

- minikube 用の app overlay
- `..\base`, `..\postgres`, `..\n8n` を読み込んだ上で `ExternalSecret` に `remoteRef.property` を追加する
- Kubernetes provider では source Secret 名と data key を明示する必要があるため、その差分だけをここに閉じ込めている

## 7. ファイル間の関係

### 7.1 通常クラスタ

```text
pnpm run home-garage -- setup
  -> root-app
  -> clusters\home
  -> clusters\base
  -> platform\core + platform\networking + platform\observability\* + apps
```

### 7.2 minikube

```text
pnpm run home-garage -- setup-minikube
  -> publish-local-repo-minikube
  -> setup (--repo-url git://... --cluster-path clusters/minikube)
  -> seed-minikube-secrets
  -> clusters\minikube
  -> platform\core\minikube + apps\minikube
```

### 7.3 secret の流れ

実クラスタ:

```text
Infisical
  -> platform\core\cluster-secret-store.yaml
  -> apps\*\ExternalSecret
  -> Secret
  -> Pod
```

minikube:

```text
seed-minikube-secrets
  -> Secret (external-secrets namespace)
  -> platform\core\minikube\cluster-secret-store.yaml
  -> apps\minikube\kustomization.yaml の property patch
  -> apps\*\ExternalSecret
  -> Secret
  -> Pod
```
