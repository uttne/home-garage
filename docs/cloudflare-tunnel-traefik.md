# Cloudflare Tunnel と Traefik Ingress の流れ

このドキュメントでは、Cloudflare Tunnel から来たアクセスが Kubernetes クラスタ内の `myhome-tools` に届くまでの流れを説明します。

この repository では、Cloudflare Tunnel はアプリに直接ルーティングするのではなく、クラスタ内の Traefik にリクエストを渡します。アプリごとの振り分けは Traefik Ingress Controller が行います。

## 全体像

リクエストの流れは次の通りです。

```text
利用者
  -> Cloudflare
  -> Cloudflare Tunnel
  -> cloudflared Pod
  -> traefik.kube-system.svc.cluster.local:80
  -> Traefik Ingress Controller
  -> myhome-tools の Ingress ルール
  -> myhome-tools の Service
  -> frontend / backend Pod
```

重要なのは、Cloudflare Tunnel が担当する範囲と Traefik が担当する範囲が分かれていることです。

- Cloudflare Tunnel は、外部からのアクセスをクラスタ内の Traefik まで届けます。
- Traefik は、届いた HTTP リクエストの `Host` や path を見て、どの Kubernetes Service に渡すかを決めます。
- `myhome-tools` の frontend / backend Pod は、Traefik から Service 経由でリクエストを受け取ります。

## Cloudflare Tunnel の役割

`apps/cloudflare-tunnel/deployment.yaml` では、`cloudflared` Pod を起動しています。

```yaml
args:
  - tunnel
  - --no-autoupdate
  - --metrics
  - 0.0.0.0:2000
  - run
  - --token
  - $(TUNNEL_TOKEN)
```

`TUNNEL_TOKEN` は `apps/cloudflare-tunnel/externalsecret.yaml` により、GCP Secret Manager の `CLOUDFLARE_TUNNEL_TOKEN` から Kubernetes Secret として作られます。

```yaml
data:
  - secretKey: token
    remoteRef:
      key: CLOUDFLARE_TUNNEL_TOKEN
```

この token によって、`cloudflared` は Cloudflare 側に登録された Tunnel 設定で起動します。

今回の Tunnel 設定では、Cloudflare 側の origin が次のようになっています。

```text
http://traefik.kube-system.svc.cluster.local:80
```

そのため、Cloudflare に届いたリクエストは Tunnel を通ってクラスタ内の Traefik Service に転送されます。

## Traefik とは何か

Traefik はリバースプロキシであり、Kubernetes では Ingress Controller として使われることがあります。

Ingress Controller としての Traefik は、クラスタ内の `Ingress` リソースを監視し、そのルールに従って HTTP リクエストを各 Service に振り分けます。

ここで混同しやすい点は、`Ingress` 自体は Pod ではないということです。

- `Ingress` は、HTTP ルーティングのルール定義です。
- `ingressClassName: traefik` は、その Ingress ルールを Traefik に処理してもらうための指定です。
- 実際に通信を受けて転送する Pod は、クラスタにインストール済みの Traefik Pod です。

つまり、アプリごとに Ingress Pod が立つわけではありません。通常はクラスタ共通の Traefik があり、複数の Ingress ルールを見て、Host や path ごとに振り分けます。

ただし、Traefik がクラスタ内のすべての通信を担当するわけではありません。Pod 間通信や通常の Service 通信は Traefik を通りません。Traefik が担当するのは、Ingress として公開された HTTP/HTTPS の入口です。

## myhome-tools の Ingress

`apps/myhome-tools/values.yaml` では、Ingress が有効化されています。

```yaml
ingress:
  enabled: true
  className: traefik
  host: myhome-tools.local
  tls: []
```

この `className: traefik` によって、Helm chart から作られる Ingress は Traefik に処理されます。

`host: myhome-tools.local` はローカル用の初期値です。実際に `task deploy-myhome-tools` でデプロイするときは、`Taskfile.yml` により次の値で上書きされます。

```yaml
--set-string ingress.host="myhome-tools.${MYHOME_DOMAIN}"
```

つまり、デプロイ後の Ingress は `myhome-tools.${MYHOME_DOMAIN}` という Host に対するルールになります。

Cloudflare から Traefik に届いたリクエストの `Host` ヘッダーが `myhome-tools.${MYHOME_DOMAIN}` であれば、Traefik はこの Ingress ルールに一致すると判断し、`myhome-tools` の Service に転送します。

## なぜ myhome-tools に振り分けられるのか

Cloudflare Tunnel 側の設定では、origin として Traefik を指定しています。

```text
http://traefik.kube-system.svc.cluster.local:80
```

この時点では、Tunnel は `myhome-tools` を直接知っている必要はありません。Tunnel は Traefik まで届けるだけです。

その後、Traefik が Kubernetes の Ingress ルールを見て、次の条件で `myhome-tools` に振り分けます。

- `myhome-tools` の Ingress が作成されていること
- その Ingress の `ingressClassName` または `className` が `traefik` であること
- Ingress の host が `myhome-tools.${MYHOME_DOMAIN}` であること
- Cloudflare から届くリクエストの `Host` ヘッダーも `myhome-tools.${MYHOME_DOMAIN}` であること

この条件が揃うと、Traefik は Host ベースのルーティングにより、該当する Service へリクエストを流します。

## frontend と backend への振り分け

`myhome-tools` の Helm chart は、この repository 外の OCI chart として参照されています。

```yaml
helm upgrade --install myhome-tools oci://ghcr.io/uttne/charts/myhome-tools
```

そのため、この repository の `values.yaml` だけでは、最終的に chart がどの Service や path を作るかの詳細は見えません。

ただし、一般的には chart 側で次のようなリソースが作られます。

- frontend Deployment
- backend Deployment
- frontend Service
- backend Service
- Ingress

Traefik は Ingress の host/path ルールに従って、frontend または backend の Service に転送します。例えば `/` を frontend に、`/api` を backend に向けるような構成であれば、その path ルールに従って振り分けられます。

## デプロイ時に関係する task

`task deploy-myhome-tools` は、Cloudflare Tunnel と `myhome-tools` の両方をデプロイします。

```yaml
cmds:
  - task: deploy-cloudflare-tunnel
  - kubectl create namespace myhome --dry-run=client -o yaml | kubectl apply -f -
  - kubectl apply -f apps/myhome-tools/externalsecret.yaml
  - >
    helm upgrade --install myhome-tools oci://ghcr.io/uttne/charts/myhome-tools
    --version 0.1.0
    --namespace myhome --create-namespace
    -f apps/myhome-tools/values.yaml
    --set-string backend.env.FRONTEND_ORIGIN="https://myhome-tools.${MYHOME_DOMAIN}"
    --set-string backend.env.SECURE_COOKIES="true"
    --set-string ingress.host="myhome-tools.${MYHOME_DOMAIN}"
```

ここで `deploy-cloudflare-tunnel` が先に呼ばれるため、クラスタ内に `cloudflared` が用意されます。その後、`myhome-tools` の Helm release が作られ、Traefik が処理する Ingress が追加されます。

## 動作確認

Traefik がクラスタ内にあるか確認します。

```powershell
kubectl get svc -n kube-system traefik
kubectl get pod -n kube-system -l app.kubernetes.io/name=traefik
```

`cloudflared` が動いているか確認します。

```powershell
kubectl get pod -n cloudflare
kubectl logs -n cloudflare deploy/cloudflared
```

`myhome-tools` の Ingress が作られているか確認します。

```powershell
kubectl get ingress -n myhome
kubectl describe ingress -n myhome
```

Ingress の `Host` が `myhome-tools.${MYHOME_DOMAIN}` になっていて、`IngressClass` が `traefik` になっていれば、Traefik のルーティング対象になっています。

## よくあるハマりどころ

### Tunnel は動いているが myhome-tools に届かない

Cloudflare Tunnel の origin が Traefik を向いているか確認します。

```text
http://traefik.kube-system.svc.cluster.local:80
```

また、Cloudflare 側の public hostname と Kubernetes の Ingress host が一致している必要があります。例えば Cloudflare 側が `myhome-tools.example.com` を受けているなら、Ingress の host も `myhome-tools.example.com` である必要があります。

### Traefik まで届くが 404 になる

Traefik の 404 は、Traefik までは届いているが一致する Ingress ルールがないときによく発生します。

次を確認してください。

- `kubectl get ingress -n myhome` で Ingress が存在すること
- Ingress の host が Cloudflare 側の public hostname と一致していること
- Ingress class が `traefik` になっていること
- path ルールがリクエスト path に一致していること

### backend の cookie や origin で問題が出る

`task deploy-myhome-tools` では、Cloudflare Tunnel 公開向けに次の値を上書きしています。

```yaml
--set-string backend.env.FRONTEND_ORIGIN="https://myhome-tools.${MYHOME_DOMAIN}"
--set-string backend.env.SECURE_COOKIES="true"
```

公開 URL が `https://myhome-tools.${MYHOME_DOMAIN}` と異なる場合は、`FRONTEND_ORIGIN` と Ingress host の整合性を確認してください。

## 関連ファイル

- `apps/cloudflare-tunnel/deployment.yaml`
- `apps/cloudflare-tunnel/externalsecret.yaml`
- `apps/myhome-tools/values.yaml`
- `apps/myhome-tools/externalsecret.yaml`
- `Taskfile.yml`
