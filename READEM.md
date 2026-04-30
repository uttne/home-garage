# home-garage

家庭内アプリケーションを載せるための GitOps ベース Kubernetes 基盤リポジトリです。  
ArgoCD を入口として、External Secrets Operator、Istio、VictoriaMetrics、Grafana、Loki、Fluent Bit、Tempo、OpenTelemetry Collector、そしてアプリケーション群を段階的に同期します。

## ドキュメント案内

詳細ドキュメントは `docs\` 配下に整理しています。

- 運用手順: `docs\operations-guide.md`
- 構成リファレンス: `docs\configuration-reference.md`
- ドキュメント一覧: `docs\README.md`

## 採用している主要コンポーネント

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

## リポジトリ構成

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
