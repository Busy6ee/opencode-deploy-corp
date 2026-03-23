#!/bin/bash
# OpenCode 온프레미스 신규 서버 셋업 스크립트
# 대화형으로 provider 정보를 입력받아 설치 및 설정을 자동화한다.

set -euo pipefail

# ── 상수 ──────────────────────────────────────────────
AIDM_ROOT="/opt/aidm"
CONFIG_DIR="${AIDM_ROOT}/config"
SKILL_DIR="${CONFIG_DIR}/skill"
AIDM_OWNER="$(whoami)"
AIDM_GROUP="aidm"

# ── 0. 사전 검증 ─────────────────────────────────────
echo "=== OpenCode 온프레미스 셋업 ==="
echo ""

# sudo 권한 확인
if ! sudo -v 2>/dev/null; then
    echo "[오류] sudo 권한이 필요합니다. sudoers에 현재 사용자(${AIDM_OWNER})를 추가하세요."
    exit 1
fi

# npm 확인
if ! command -v npm &>/dev/null; then
    echo "[오류] npm이 설치되어 있지 않습니다. Node.js/npm을 먼저 설치하세요."
    exit 1
fi

# 레포 위치 감지
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "${SCRIPT_DIR}/AGENTS.md" ]; then
    REPO_SOURCE="${SCRIPT_DIR}"
else
    REPO_SOURCE=""
fi

# ── 1. 대화형 입력 ───────────────────────────────────
echo "--- 프로바이더 설정 ---"
echo ""

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
read -rp "모델 ID (예: qwen2.5-coder:32b): " MODEL_ID
read -rp "모델 표시 이름 (예: Qwen 2.5 Coder 32B): " MODEL_NAME

echo ""
read -rp "컨텍스트 제한 [32768]: " CONTEXT_LIMIT
CONTEXT_LIMIT="${CONTEXT_LIMIT:-32768}"

read -rp "출력 제한 [8192]: " OUTPUT_LIMIT
OUTPUT_LIMIT="${OUTPUT_LIMIT:-8192}"

echo ""
read -rp "config.json \$schema URL (사내 GitHub raw URL): " SCHEMA_URL

echo ""
read -rp "Claude Code 시스템 비활성화 (y/N): " DISABLE_CLAUDE
DISABLE_CLAUDE="${DISABLE_CLAUDE:-N}"

echo ""
echo "--- 입력 확인 ---"
echo "\$schema: ${SCHEMA_URL}"
echo "프로바이더: http://${PROVIDER_HOST}:${PROVIDER_PORT}/v1"
echo "모델: ${MODEL_ID} (${MODEL_NAME})"
echo "컨텍스트: ${CONTEXT_LIMIT}, 출력: ${OUTPUT_LIMIT}"
echo ""
read -rp "계속 진행하시겠습니까? (Y/n): " CONFIRM
if [[ "${CONFIRM}" =~ ^[nN]$ ]]; then
    echo "취소되었습니다."
    exit 0
fi

echo ""

# ── 2. [1/5] 디렉토리 생성 + OpenCode 설치 ───────────
echo "[1/5] OpenCode 설치..."

sudo mkdir -p "${AIDM_ROOT}"/{bin,lib,config/skill,src}

if [ -x "${AIDM_ROOT}/bin/opencode" ]; then
    echo "  이미 설치됨. 건너뜀."
else
    sudo npm install -g opencode-ai --prefix "${AIDM_ROOT}"
    echo "  설치 완료."
fi

# ── 3. [2/5] 레포 클론 ──────────────────────────────
echo "[2/5] 레포 배치..."

REPO_DEST="${AIDM_ROOT}/src/opencode-deploy-corp"

if [ -n "${REPO_SOURCE}" ]; then
    # 스크립트가 레포 안에서 실행됨
    if [ "${REPO_SOURCE}" != "${REPO_DEST}" ]; then
        if [ ! -e "${REPO_DEST}" ]; then
            sudo ln -s "${REPO_SOURCE}" "${REPO_DEST}"
            echo "  심볼릭 링크 생성: ${REPO_SOURCE} -> ${REPO_DEST}"
        else
            echo "  이미 존재. 건너뜀."
        fi
    else
        echo "  이미 대상 경로에 위치. 건너뜀."
    fi
else
    # 레포 외부에서 실행 -- clone 필요
    if [ -d "${REPO_DEST}/.git" ]; then
        echo "  이미 존재. git pull 실행..."
        cd "${REPO_DEST}" && sudo git pull
    else
        REPO_URL=""
        read -rp "  레포 Git URL: " REPO_URL
        if [ -z "${REPO_URL}" ]; then
            echo "  [경고] URL 미입력. 레포 클론 건너뜀."
        else
            sudo git clone "${REPO_URL}" "${REPO_DEST}"
            echo "  클론 완료."
        fi
    fi
fi

# REPO_SOURCE 재설정 (이후 스킬 링크에 사용)
if [ -d "${REPO_DEST}" ]; then
    REPO_SOURCE="${REPO_DEST}"
elif [ -L "${REPO_DEST}" ]; then
    REPO_SOURCE="$(readlink -f "${REPO_DEST}")"
fi

# ── 4. [3/5] opencode.jsonc 생성 ────────────────────
echo "[3/5] 설정 파일 생성..."

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
  "permission": {
    "webfetch": "deny",
    "websearch": "deny",
    "fetch": "deny"
  },
  "provider": {
    "ollama": {
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

# ── 5. [4/5] 스킬 심볼릭 링크 ───────────────────────
echo "[4/5] 스킬 심볼릭 링크..."

if [ -d "${REPO_SOURCE}/skills" ]; then
    for skill_dir in "${REPO_SOURCE}/skills/"*/; do
        [ -d "${skill_dir}" ] || continue
        skill_name="$(basename "${skill_dir}")"
        target="${SKILL_DIR}/${skill_name}"
        if [ ! -e "${target}" ]; then
            sudo ln -s "${skill_dir}" "${target}"
            echo "  링크 생성: ${skill_name}"
        else
            echo "  이미 존재: ${skill_name}"
        fi
    done
else
    echo "  skills/ 디렉토리 없음. 건너뜀."
fi

# ── 6. [5/5] opencode.sh 생성 ────────────────────────
echo "[5/5] 환경 설정 스크립트 생성..."

OPENCODE_SH="${AIDM_ROOT}/opencode.sh"

sudo tee "${OPENCODE_SH}" > /dev/null << 'PROFILEEOF'
#!/bin/bash
# /opt/aidm/opencode.sh -- OpenCode 온프레미스 환경 설정
# aidm 그룹 사용자만 source 가능

export PATH="/opt/aidm/bin:$PATH"
export OPENCODE_CONFIG_DIR="/opt/aidm/config"

# 아웃바운드 차단 (7종)
export OPENCODE_DISABLE_MODELS_FETCH=true
export OPENCODE_DISABLE_AUTOUPDATE=true
export OPENCODE_DISABLE_LSP_DOWNLOAD=true
export OPENCODE_DISABLE_EXTERNAL_SKILLS=true
export OPENCODE_DISABLE_SHARE=true
export OPENCODE_DISABLE_DEFAULT_PLUGINS=true
PROFILEEOF

# OPENCODE_DISABLE_CLAUDE_CODE 조건부 추가
if [[ "${DISABLE_CLAUDE}" =~ ^[yY]$ ]]; then
    echo 'export OPENCODE_DISABLE_CLAUDE_CODE=true' | sudo tee -a "${OPENCODE_SH}" > /dev/null
fi

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
NOPROXYEOF

sudo chmod +x "${OPENCODE_SH}"
echo "  생성 완료: ${OPENCODE_SH}"

# ── 7. 소유권 및 권한 설정 ───────────────────────────
echo ""
echo "소유권/권한 설정..."

sudo chown -R "${AIDM_OWNER}:${AIDM_GROUP}" "${AIDM_ROOT}"
sudo chmod -R 2750 "${AIDM_ROOT}"

echo "  ${AIDM_ROOT} -> ${AIDM_OWNER}:${AIDM_GROUP} (2750)"

# ── 8. 완료 요약 ────────────────────────────────────
echo ""
echo "===== 설치 완료 ====="
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
