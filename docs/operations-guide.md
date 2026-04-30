# home-garage 運用手順ガイド

このドキュメントは、基盤の構築、minikube 検証、確認作業、日常運用で使う手順をまとめたものです。  
設計意図や各 manifest の詳細は `docs\configuration-reference.md` を参照してください。

## 1. 前提条件

以下を利用できる状態で作業します。

- `node`
- `pnpm`
- `kubectl`
- `helm`
- `git`
- 接続可能な `k3s` または `minikube`

最初に依存関係を入れます。

```powershell
pnpm install
```

補足:

- 実クラスタ (`clusters\home`) では、Infisical 側の secret と認証情報が揃っている必要があります
- minikube では、`seed-minikube-secrets` が検証用の source Secret を生成します
- 外部公開は Cloudflare Tunnel 前提のため、n8n Ingress 自体には TLS Secret を持たせていません

## 2. 標準クラスタの bootstrap

```powershell
pnpm run home-garage -- setup
```

必要なら repo URL と cluster path を差し替えます。

```powershell
pnpm run home-garage -- setup --repo-url https://github.com/uttne/home-garage.git --cluster-path clusters/home
```

この bootstrap では次の流れで初期化します。

1. ArgoCD を導入する
2. Infisical 認証情報が設定済みなら Secret を投入する
3. `root-app` を apply する
4. `clusters\home` を入口に App-of-Apps を展開する
5. sync wave 順に platform と apps を同期する

## 3. Infisical 認証情報の投入

実クラスタで External Secrets Operator を Ready にするには、Infisical Universal Auth の credential を投入します。

PowerShell:

```powershell
$env:INFISICAL_CLIENT_ID = "..."
$env:INFISICAL_CLIENT_SECRET = "..."
pnpm run home-garage -- bootstrap-infisical-credentials
```

Bash:

```bash
export INFISICAL_CLIENT_ID=...
export INFISICAL_CLIENT_SECRET=...
pnpm run home-garage -- bootstrap-infisical-credentials
```

動作メモ:

- 両方の環境変数が設定されていれば `external-secrets\infisical-universal-auth` を作成します
- 片方だけ設定されている場合は失敗します
- 未設定でも bootstrap 自体は進みますが、`ClusterSecretStore\platform-secrets` は Ready になりません

## 4. minikube での検証

未 push のローカル変更を含めて検証したい場合は、minikube 用コマンドを使います。

```powershell
pnpm run home-garage -- setup-minikube
```

このコマンドは次を順番に実行します。

1. `publish-local-repo-minikube`
2. `setup --repo-url git://home-garage-git.argocd.svc.cluster.local/home-garage --cluster-path clusters/minikube`
3. `seed-minikube-secrets`

### minikube 検証の意味

- ローカル working tree を一時 Git bundle 化して、クラスター内の `git daemon` へ公開します
- ArgoCD は GitHub ではなく in-cluster Git サービスから manifest を取得します
- そのため、未 commit / 未 push の変更でも GitOps の実動作に近い形で検証できます

### minikube 側で追加されるもの

- `argocd` namespace 上の一時 Git サービス
- `external-secrets` namespace 上の検証用 source Secret
- `clusters\minikube` overlay 経由の repo URL / path 差し替え

## 5. 構築後の確認

基本確認は次のコマンドを使います。

```powershell
pnpm run home-garage -- validate
```

主に以下を確認します。

- 必須 namespace の存在
- ArgoCD Applications の Sync / Health
- `ClusterSecretStore\platform-secrets`
- `ExternalSecret` の解決状態
- observability / `n8n` namespace の Pod 状態

## 6. 日常運用で見るポイント

### 6.1 ArgoCD の同期順

アプリは以下の sync wave で流れます。

- wave 0: `platform-core`
- wave 1: `platform-networking`
- wave 2: `platform-observability-metrics`
- wave 3: `platform-observability-logging`
- wave 4: `platform-observability-tracing`
- wave 5: `apps`

問題切り分けでは、後段の異常を見つけたときに前段の wave を先に確認します。

### 6.2 secret 更新時の基本方針

実クラスタ:

1. Infisical 側の値を更新する
2. `ClusterSecretStore` が Ready であることを確認する
3. 対象 `ExternalSecret` と生成された `Secret` を確認する
4. 必要なら ArgoCD sync または対象 workload の再起動を行う

minikube:

1. `pnpm run home-garage -- seed-minikube-secrets` を再実行する
2. `ExternalSecret` の同期結果を確認する
3. 必要なら関連 Pod を再作成する

### 6.3 ローカル変更を検証してから push したい場合

推奨手順:

1. 変更を working tree に反映する
2. `pnpm run home-garage -- setup-minikube` で in-cluster Git を更新して再検証する
3. `pnpm run home-garage -- validate` で状態確認する
4. 問題がなければ commit / push に進む

## 7. 代表的な確認対象

### PostgreSQL

- `apps\postgres\configmap.yaml` の初期化処理は idempotent です
- 既存 PVC が残っている状態でも、ロールと DB の再同期に耐える設計です
- DB には `sidecar.istio.io/inject: "false"` を設定しています

### n8n

- PostgreSQL を待ってから起動します
- DB 接続情報と暗号化キーは Secret から受け取ります
- `WEBHOOK_URL` は現在 `http://my-home-n8n.local/` を前提にしています
- 公開経路の TLS は Cloudflare Tunnel 側で扱う前提です
- `sidecar.istio.io/inject: "true"` により Istio sidecar を注入します

### Grafana

- 最初から VictoriaMetrics / Loki / Tempo を datasource として持ちます
- minikube では volume 権限問題を避けるため `initChownData.enabled=false` を使っています

## 8. トラブルシュートの見方

確認の順番は以下を推奨します。

1. ArgoCD Application の `Sync` / `Health`
2. `ClusterSecretStore` と `ExternalSecret`
3. 対象 namespace の Pod 状態
4. Ingress / Service / Endpoint
5. Grafana、Loki、Tempo、VictoriaMetrics の接続状況

特に注意する点:

- secret backend が解決できないと app 側 Pod より先に `ExternalSecret` が失敗します
- minikube では GitHub を見ていないため、まず in-cluster Git の再公開が必要か確認します
- apps の異常は、前段の `platform\` 側コンポーネント未整備が原因のことがあります
