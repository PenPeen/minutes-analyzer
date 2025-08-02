#!/bin/bash

set -e

# カラー定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ログ出力関数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# プロジェクト情報
PROJECT_NAME="議事録口出しBot"
REPO_URL="https://github.com/your-username/minutes-analyzer"

echo ""
echo "🚀 $PROJECT_NAME 初期セットアップ"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# プロジェクトルートの確認
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

log_info "プロジェクトディレクトリ: $PROJECT_ROOT"

# 前提条件のチェック
check_prerequisites() {
    log_info "前提条件をチェック中..."

    local missing_deps=()
    local deps=(
        "docker:Docker"
        "docker-compose:Docker Compose"
        "terraform:Terraform"
        "aws:AWS CLI"
        "jq:jq"
        "ruby:Ruby"
        "bundle:Bundler"
    )

    for dep_info in "${deps[@]}"; do
        local cmd="${dep_info%:*}"
        local name="${dep_info#*:}"

        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$name")
            log_error "$name が見つかりません"
        else
            local version=""
            case "$cmd" in
                "docker")
                    version="$(docker --version 2>/dev/null | head -1)"
                    ;;
                "terraform")
                    version="$(terraform --version 2>/dev/null | head -1)"
                    ;;
                "aws")
                    version="$(aws --version 2>/dev/null)"
                    ;;
                "ruby")
                    version="$(ruby --version 2>/dev/null)"
                    ;;
                *)
                    version="✅"
                    ;;
            esac
            log_success "$name: $version"
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo ""
        log_error "以下の依存関係が不足しています:"
        for dep in "${missing_deps[@]}"; do
            echo "  • $dep"
        done
        echo ""
        echo "📖 インストール方法:"
        echo ""
        echo "🍎 macOS (Homebrew):"
        echo "  brew install docker terraform awscli jq ruby"
        echo "  brew install --cask docker"
        echo ""
        echo "🐧 Ubuntu/Debian:"
        echo "  sudo apt-get update"
        echo "  sudo apt-get install docker.io docker-compose terraform awscli jq ruby ruby-bundler"
        echo ""
        echo "🔴 CentOS/RHEL:"
        echo "  sudo yum install docker terraform awscli jq ruby ruby-devel"
        echo ""
        exit 1
    fi

    log_success "✅ すべての前提条件が満たされています"
}

# 環境ファイルの作成
setup_environment_files() {
    log_info "環境設定ファイルを作成中..."

    cd "$PROJECT_ROOT"

    # .env.local の作成
    if [ ! -f ".env.local" ]; then
        if [ -f "env.local.sample" ]; then
            cp env.local.sample .env.local
            log_success ".env.local ファイルを作成しました"
        else
            log_error "env.local.sample ファイルが見つかりません"
            exit 1
        fi
    else
        log_warning ".env.local ファイルは既に存在します"
    fi

    # .gitignore の確認
    if [ -f ".gitignore" ]; then
        log_success ".gitignore ファイルが確認されました"
    else
        log_warning ".gitignore ファイルが見つかりません"
    fi
}

# Ruby依存関係の確認
check_ruby_dependencies() {
    log_info "Ruby環境を確認中..."

    cd "$PROJECT_ROOT/lambda"

    if [ ! -f "Gemfile" ]; then
        log_error "lambda/Gemfile が見つかりません"
        exit 1
    fi

    # Bundlerのバージョン確認
    if command -v bundle &> /dev/null; then
        local bundler_version=$(bundle --version 2>/dev/null)
        log_success "Bundler: $bundler_version"
    else
        log_warning "Bundlerが見つかりません。インストール中..."
        gem install bundler
    fi

    log_success "Ruby環境が確認されました"
}

# ディレクトリ構造の確認
verify_project_structure() {
    log_info "プロジェクト構造を確認中..."

    local required_dirs=(
        "infrastructure"
        "infrastructure/environments/local"
        "infrastructure/modules"
        "lambda"
        "lambda/src"
        "docs"
        "scripts"
    )

    local missing_dirs=()

    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$PROJECT_ROOT/$dir" ]; then
            missing_dirs+=("$dir")
        fi
    done

    if [ ${#missing_dirs[@]} -ne 0 ]; then
        log_error "以下のディレクトリが見つかりません:"
        for dir in "${missing_dirs[@]}"; do
            echo "  • $dir"
        done
        exit 1
    fi

    log_success "プロジェクト構造が確認されました"
}

# 使用方法の表示
show_next_steps() {
    echo ""
    echo "🎉 初期セットアップが完了しました！"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_warning "⚠️  次の設定が必要です:"
    echo ""
    echo "1. 📝 Gemini API キーの設定"
    echo "   • Google AI Studio でAPIキーを取得: https://makersuite.google.com/app/apikey"
    echo "   • .env.local ファイルを編集: vim .env.local"
    echo "   • GEMINI_API_KEY=your_api_key_here を設定"
    echo ""
    echo "2. 📢 Slack通知の設定（オプション）"
    echo "   • Slack Webhook URLを取得"
    echo "   • .env.local の SLACK_ERROR_WEBHOOK_URL を設定"
    echo ""
    echo "📋 次のステップ:"
    echo ""
    echo "  # 1. 環境変数を設定"
    echo "  vim .env.local"
    echo ""
    echo "  # 2. 開発環境を起動"
    echo "  make dev-setup"
    echo ""
    echo "  # 3. APIテストを実行"
    echo "  make test-api"
    echo ""
    echo "  # 4. ヘルプを表示"
    echo "  make help"
    echo ""
    log_info "詳細なドキュメントは README.md を参照してください"
}

# メイン実行
main() {
    check_prerequisites
    verify_project_structure
    setup_environment_files
    check_ruby_dependencies
    show_next_steps
}

# スクリプト実行
main "$@"
