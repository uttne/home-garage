# home-garage 🔧

自宅の で使用するサービスを管理するためのレポジトリです。
ArgoCD を中心に、管理ツール群（Prometheus, Grafana 等）や自作アプリケーションのデプロイメントを定義しています。

## 🚀 Bootstrap (セットアップ)

このリポジトリを新しい Kubernetes クラスターに適用し、GitOps の同期を開始する手順です。

### 前提条件 (Prerequisites)

コマンドを実行する端末に、以下のツールがインストールされ、パスが通っている必要があります。

- **Kubernetes Cluster**: 接続可能なクラスターがあること
- **kubectl**: クラスターへのアクセスが設定されていること (`~/.kube/config` 等)
- **Helm**: ArgoCD のインストールに使用します
- **Git**: リポジトリの取得に使用します

### 実行方法 (Usage)

1. リポジトリをクローンし、ディレクトリに移動します。

    ```bash
    git clone [https://github.com/uttne/home-garage.git](https://github.com/uttne/home-garage.git)
    cd home-garage
    ```

2. bootstrap スクリプトに実行権限を付与し、実行します。

    ```bash
    chmod +x bootstrap/setup.sh
    ./bootstrap/setup.sh
    ```

## 実行される処理 (What happens)

スクリプトを実行すると、自動的に以下の処理が行われます。

1. ArgoCD のインストール
   - argocd 名前空間を作成し、Helm を使用して公式チャートから ArgoCD をインストールします。
2. 待機
   - ArgoCD サーバーが正常に起動するまで待機します。
3. Root App (App of Apps) の適用
   - bootstrap/root-app.yaml を適用します。
   - これにより、ArgoCD がこのリポジトリの system/ ディレクトリの監視を開始し、今後追加されるツール群が自動的に同期（デプロイ）されるようになります。
4. パスワードの出力
   - 最後に、ArgoCD の初期管理者パスワード（admin ユーザー用）をデコードしてターミナルに表示します。
