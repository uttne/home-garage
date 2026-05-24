# eso-store の使い方

`charts/eso-store` は External Secrets Operator 向けの `ClusterSecretStore` を Helm でデプロイするための chart です。  
この repository では `task deploy-eso-store` で以下を作成します。

- `external-secrets` namespace の `ServiceAccount`
- cluster-scoped な `ClusterSecretStore` (`gcp-secret-store`)

## 前提

- `helm`, `kubectl`, `task` が使えること
- Kubernetes クラスタにアクセスできること
- `.env` に以下の値が設定されていること

```env
GCP_PROJECT_ID=
GCP_WIF_AUDIENCE=
GCP_WIF_SERVICE_ACCOUNT_NAME=
GCP_WIF_SERVICE_ACCOUNT_NAMESPACE=
```

`Taskfile.yml` では `.env` を自動で読み込みます。

## デプロイ手順

まず External Secrets Operator 本体を入れます。

```powershell
task install-eso
```

次に `ClusterSecretStore` をデプロイします。

```powershell
task deploy-eso-store
```

この task は内部で以下の値を Helm chart に渡します。

- `projectID` ← `GCP_PROJECT_ID`
- `audience` ← `GCP_WIF_AUDIENCE`
- `serviceAccountName` ← `GCP_WIF_SERVICE_ACCOUNT_NAME`
- `serviceAccountNamespace` ← `GCP_WIF_SERVICE_ACCOUNT_NAMESPACE`

## 何が作られるか

`charts/eso-store` のテンプレートは次の構成です。

### 1. ServiceAccount

`external-secrets` namespace など、指定した namespace に `ServiceAccount` を作ります。

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: <serviceAccountName>
  namespace: <serviceAccountNamespace>
```

### 2. ClusterSecretStore

External Secrets Operator が GCP Secret Manager に接続するための `ClusterSecretStore` を作ります。

```yaml
apiVersion: external-secrets.io/v1
kind: ClusterSecretStore
metadata:
  name: gcp-secret-store
spec:
  provider:
    gcpsm:
      projectID: <GCP_PROJECT_ID>
      auth:
        workloadIdentityFederation:
          serviceAccountRef:
            name: <GCP_WIF_SERVICE_ACCOUNT_NAME>
            namespace: <GCP_WIF_SERVICE_ACCOUNT_NAMESPACE>
          audience: <GCP_WIF_AUDIENCE>
```

## 利用手順

`ClusterSecretStore` を作成したら、各 namespace で `ExternalSecret` を作成して使います。  
サンプルは `sample/demo-externalsecret-clustersecretstore.yaml` にあります。

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: demo
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: my-external-secret
  namespace: demo
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: gcp-secret-store
  target:
    name: k3s-app-secret
  data:
  - secretKey: my-db-pass
    remoteRef:
      key: my-test-password
```

適用は次の通りです。

```powershell
kubectl apply -f .\sample\demo-externalsecret-clustersecretstore.yaml
```

上の例では、GCP Secret Manager の `my-test-password` を読み取り、Kubernetes Secret `k3s-app-secret` の `my-db-pass` に書き込みます。

## 動作確認

まず `ClusterSecretStore` が Ready になっているか確認します。

```powershell
kubectl describe clustersecretstore gcp-secret-store
```

`Conditions` に `Type: Ready` かつ `Status: True` が出ていれば、Store の初期化は成功しています。

次に `ExternalSecret` の状態を確認します。

```powershell
kubectl describe externalsecret my-external-secret -n demo
```

`Conditions` に `Type: Ready` かつ `Status: True` が出ていれば、外部シークレットの取得に成功しています。

生成された Kubernetes Secret は次で確認できます。

```powershell
kubectl get secret k3s-app-secret -n demo -o yaml
```

特定キーの値を確認する場合は Base64 をデコードします。

```powershell
$encoded = kubectl get secret k3s-app-secret -n demo -o jsonpath="{.data.my-db-pass}"
[System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encoded))
```

## よくあるハマりどころ

### `ClusterSecretStore "gcp-secret-store" is not ready`

`ClusterSecretStore` 側の初期化に失敗しています。まずこちらを確認します。

```powershell
kubectl describe clustersecretstore gcp-secret-store
```

特に `serviceAccountRef.name` だけでなく `serviceAccountRef.namespace` も正しく設定されている必要があります。  
`ClusterSecretStore` は cluster-scoped なので、Helm の `--namespace external-secrets` だけでは参照先の `ServiceAccount` namespace は解決されません。

### `unknown field "spec.secretStoreRef.namespace"`

`ExternalSecret` の `secretStoreRef` に `namespace` は書けません。  
この repository の `eso-store` は `ClusterSecretStore` を作るので、`ExternalSecret` 側は次のように指定します。

```yaml
secretStoreRef:
  kind: ClusterSecretStore
  name: gcp-secret-store
```

### `ServiceAccount "... " not found`

`ClusterSecretStore` が参照している `ServiceAccount` の namespace がずれている可能性があります。  
`.env` の `GCP_WIF_SERVICE_ACCOUNT_NAMESPACE` と、実際に `ServiceAccount` が作成されている namespace を確認してください。

## 関連ファイル

- `Taskfile.yml`
- `charts/eso-store/Chart.yaml`
- `charts/eso-store/values.yaml`
- `charts/eso-store/templates/service-account.yaml`
- `charts/eso-store/templates/cluster-secret-store.yaml`
- `sample/demo-externalsecret-clustersecretstore.yaml`
