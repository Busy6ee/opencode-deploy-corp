#!/bin/bash
# OpenCode 온프레미스 신규 서버 셋업 스크립트
# 대화형으로 provider 정보를 입력받아 설치 및 설정을 자동화한다.

set -euo pipefail

# ── 상수 ──────────────────────────────────────────────
AIDM_ROOT="/opt/aidm"
CONFIG_DIR="${AIDM_ROOT}/config"
NODE_DIR="${AIDM_ROOT}/node"
AIDM_OWNER="$(whoami)"
AIDM_GROUP="aidm"
NODE_VERSION="22.16.0"

# ── 0. 사전 검증 ─────────────────────────────────────
echo "=== OpenCode 온프레미스 셋업 ==="
echo ""

# sudo 권한 확인
if ! sudo -v 2>/dev/null; then
    echo "[오류] sudo 권한이 필요합니다. sudoers에 현재 사용자(${AIDM_OWNER})를 추가하세요."
    exit 1
fi

# tar, curl 확인 (Node.js 바이너리 설치에 필요)
for cmd in tar curl; do
    if ! command -v "${cmd}" &>/dev/null; then
        echo "[오류] ${cmd}이 설치되어 있지 않습니다."
        exit 1
    fi
done

# 아키텍처 감지
ARCH="$(uname -m)"
case "${ARCH}" in
    x86_64)  NODE_ARCH="x64" ;;
    aarch64) NODE_ARCH="arm64" ;;
    *)
        echo "[오류] 지원하지 않는 아키텍처: ${ARCH}"
        exit 1
        ;;
esac

# ── 1. 대화형 입력 ───────────────────────────────────
echo "--- 프로바이더 설정 ---"
echo ""

read -rp "프로바이더 ID (예: ollama, vllm): " PROVIDER_ID
PROVIDER_ID="${PROVIDER_ID:-ollama}"

read -rp "프로바이더 서버주소:포트 (예: 192.168.1.100:11434): " PROVIDER_ADDR

if [[ "${PROVIDER_ADDR}" == *:* ]]; then
    PROVIDER_HOST="${PROVIDER_ADDR%%:*}"
    PROVIDER_PORT="${PROVIDER_ADDR##*:}"
else
    PROVIDER_HOST="${PROVIDER_ADDR}"
    PROVIDER_PORT="11434"
    echo "  포트 미지정 -- 기본값 11434 사용"
fi

if [ -z "${PROVIDER_HOST}" ]; then
    echo "[오류] 서버 주소가 비어 있습니다."
    exit 1
fi

echo ""
read -rp "모델 ID [glm-4.7]: " MODEL_ID
MODEL_ID="${MODEL_ID:-glm-4.7}"

read -rp "모델 표시 이름 [GLM 4.7]: " MODEL_NAME
MODEL_NAME="${MODEL_NAME:-GLM 4.7}"

echo ""
echo "context - output = 입력 가용 토큰. 자동 compaction이 이 기준으로 발동됨"
read -rp "컨텍스트 (vLLM max_model_len) [131072]: " CONTEXT_LIMIT
CONTEXT_LIMIT="${CONTEXT_LIMIT:-131072}"

read -rp "출력 제한 [32000]: " OUTPUT_LIMIT
OUTPUT_LIMIT="${OUTPUT_LIMIT:-32000}"

echo ""
read -rp "config.json \$schema URL (사내 GitHub raw URL): " SCHEMA_URL

echo ""
echo "--- 입력 확인 ---"
echo "\$schema: ${SCHEMA_URL}"
echo "프로바이더: ${PROVIDER_ID} (http://${PROVIDER_HOST}:${PROVIDER_PORT}/v1)"
echo "모델: ${MODEL_ID} (${MODEL_NAME})"
echo "컨텍스트: ${CONTEXT_LIMIT}, 출력: ${OUTPUT_LIMIT} (입력 가용: $((CONTEXT_LIMIT - OUTPUT_LIMIT)))"
echo "Node.js: v${NODE_VERSION} (${NODE_ARCH})"
echo ""
read -rp "계속 진행하시겠습니까? (Y/n): " CONFIRM
if [[ "${CONFIRM}" =~ ^[nN]$ ]]; then
    echo "취소되었습니다."
    exit 0
fi

echo ""

# ── 2. [1/4] 디렉토리 생성 + Node.js 설치 ────────────
echo "[1/4] Node.js 설치..."

sudo mkdir -p "${AIDM_ROOT}"/{bin,lib,config/skills,node}

if [ -x "${NODE_DIR}/bin/node" ]; then
    INSTALLED_NODE_VER="$("${NODE_DIR}/bin/node" --version 2>/dev/null || echo "")"
    if [ "${INSTALLED_NODE_VER}" = "v${NODE_VERSION}" ]; then
        echo "  Node.js v${NODE_VERSION} 이미 설치됨. 건너뜀."
    else
        echo "  기존 버전(${INSTALLED_NODE_VER}) 발견. v${NODE_VERSION}으로 업데이트..."
        NODE_TARBALL="node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"
        curl -fSL "https://nodejs.org/dist/v${NODE_VERSION}/${NODE_TARBALL}" -o "/tmp/${NODE_TARBALL}"
        sudo tar -xJf "/tmp/${NODE_TARBALL}" -C "${NODE_DIR}" --strip-components=1
        rm -f "/tmp/${NODE_TARBALL}"
        echo "  업데이트 완료: $("${NODE_DIR}/bin/node" --version)"
    fi
else
    NODE_TARBALL="node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"
    echo "  다운로드: ${NODE_TARBALL}"
    curl -fSL "https://nodejs.org/dist/v${NODE_VERSION}/${NODE_TARBALL}" -o "/tmp/${NODE_TARBALL}"
    sudo tar -xJf "/tmp/${NODE_TARBALL}" -C "${NODE_DIR}" --strip-components=1
    rm -f "/tmp/${NODE_TARBALL}"
    echo "  설치 완료: $("${NODE_DIR}/bin/node" --version)"
fi

# 이후 단계에서 로컬 node/npm 사용
export PATH="${NODE_DIR}/bin:${PATH}"
echo "  node: $(node --version), npm: $(npm --version)"

# ── 3. [2/4] OpenCode 설치 ───────────────────────────
echo "[2/4] OpenCode 설치..."

if [ -x "${AIDM_ROOT}/bin/opencode" ]; then
    echo "  이미 설치됨. 건너뜀."
else
    sudo env PATH="${NODE_DIR}/bin:${PATH}" "${NODE_DIR}/bin/npm" install -g opencode-ai --prefix "${AIDM_ROOT}"
    echo "  설치 완료."
fi

# ── 4. [3/4] opencode.jsonc 생성 ────────────────────
echo "[3/4] 설정 파일 생성..."

JSONC_PATH="${CONFIG_DIR}/opencode.jsonc"

if [ -f "${JSONC_PATH}" ]; then
    sudo cp "${JSONC_PATH}" "${JSONC_PATH}.bak"
    echo "  기존 파일 백업: ${JSONC_PATH}.bak"
fi

sudo tee "${JSONC_PATH}" > /dev/null << JSONEOF
{
  "\$schema": "${SCHEMA_URL}",
  "autoupdate": false,
  "share": "disabled",
  "tools": {
    "webfetch": false,
    "websearch": false,
    "fetch": false
  },
  "permission": {
    "webfetch": "deny",
    "websearch": "deny",
    "fetch": "deny"
  },
  "skills": {
    "paths": ["${CONFIG_DIR}/skills"]
  },
  "enabled_providers": ["${PROVIDER_ID}"],
  "model": "${PROVIDER_ID}/${MODEL_ID}",
  "provider": {
    "${PROVIDER_ID}": {
      "npm": "@ai-sdk/openai-compatible",
      "options": {
        "baseURL": "http://${PROVIDER_HOST}:${PROVIDER_PORT}/v1"
      },
      "models": {
        "${MODEL_ID}": {
          "name": "${MODEL_NAME}",
          "limit": {
            "context": ${CONTEXT_LIMIT},
            "output": ${OUTPUT_LIMIT}
          }
        }
      }
    }
  }
}
JSONEOF

echo "  생성 완료: ${JSONC_PATH}"

# ── 6. [4/4] opencode.sh 생성 ────────────────────────
echo "[4/4] 환경 설정 스크립트 생성..."

OPENCODE_SH="${AIDM_ROOT}/opencode.sh"

sudo tee "${OPENCODE_SH}" > /dev/null << 'PROFILEEOF'
#!/bin/bash
# /opt/aidm/opencode.sh -- OpenCode 온프레미스 환경 설정
# aidm 그룹 사용자만 source 가능

export PATH="/opt/aidm/node/bin:/opt/aidm/bin:$PATH"
export OPENCODE_CONFIG_DIR="/opt/aidm/config"

# 아웃바운드 차단 (6종)
export OPENCODE_DISABLE_MODELS_FETCH=true
export OPENCODE_DISABLE_AUTOUPDATE=true
export OPENCODE_DISABLE_LSP_DOWNLOAD=true
export OPENCODE_DISABLE_EXTERNAL_SKILLS=true
export OPENCODE_DISABLE_SHARE=true
export OPENCODE_DISABLE_DEFAULT_PLUGINS=true
PROFILEEOF

# no_proxy 블록 추가 (provider 호스트를 리터럴로 삽입)
sudo tee -a "${OPENCODE_SH}" > /dev/null << NOPROXYEOF

# 프로바이더 서버 프록시 우회
if [ -z "\${no_proxy:-}" ]; then
    export no_proxy="${PROVIDER_HOST}"
else
    case ",\${no_proxy}," in
        *",${PROVIDER_HOST},"*) ;;
        *) export no_proxy="\${no_proxy},${PROVIDER_HOST}" ;;
    esac
fi
if [ -z "\${NO_PROXY:-}" ]; then
    export NO_PROXY="${PROVIDER_HOST}"
else
    case ",\${NO_PROXY}," in
        *",${PROVIDER_HOST},"*) ;;
        *) export NO_PROXY="\${NO_PROXY},${PROVIDER_HOST}" ;;
    esac
fi
NOPROXYEOF

sudo chmod +x "${OPENCODE_SH}"
echo "  생성 완료: ${OPENCODE_SH}"

# ── 8. 소유권 및 권한 설정 ───────────────────────────
echo ""
echo "소유권/권한 설정..."

sudo chown -R "${AIDM_OWNER}:${AIDM_GROUP}" "${AIDM_ROOT}"
sudo chmod -R 2750 "${AIDM_ROOT}"

echo "  ${AIDM_ROOT} -> ${AIDM_OWNER}:${AIDM_GROUP} (2750)"

# ── 9. 완료 요약 ────────────────────────────────────
echo ""
echo "===== 설치 완료 ====="
echo "Node.js: $("${NODE_DIR}/bin/node" --version) (${NODE_DIR})"
echo "프로바이더: http://${PROVIDER_HOST}:${PROVIDER_PORT}/v1"
echo "모델: ${MODEL_ID} (${MODEL_NAME})"
echo "컨텍스트: ${CONTEXT_LIMIT}, 출력: ${OUTPUT_LIMIT}"
echo "소유권: ${AIDM_OWNER}:${AIDM_GROUP}, 권한: 2750"
echo ""
echo "적용하려면 실행 (aidm 그룹 사용자만 가능):"
echo "  source ${OPENCODE_SH}"
echo ""
echo "연결 확인:"
echo "  curl http://${PROVIDER_HOST}:${PROVIDER_PORT}/v1/models"
