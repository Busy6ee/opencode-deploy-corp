#!/bin/bash
# OpenCode 온프레미스 추가 설치 스크립트
# setup.sh로 초기 설치 후, 스킬/플러그인(npm 패키지)을 공용 경로에 설치한다.
#
# 사용법:
#   install.sh plugin <npm-패키지>[@버전]    npm 패키지를 공용 경로에 설치
#   install.sh skill  <스킬-경로>            스킬 디렉토리를 공용 스킬 경로에 심볼릭 링크

set -euo pipefail

AIDM_ROOT="${OPENCODE_AIDM_ROOT:-/opt/aidm}"
NODE_DIR="${AIDM_ROOT}/node"
SKILLS_DIR="${AIDM_ROOT}/config/skills"
SYSTEM_CA_BUNDLE="${SYSTEM_CA_BUNDLE:-/etc/pki/tls/certs/ca-bundle.crt}"

usage() {
    echo "사용법:"
    echo "  $0 plugin <npm-패키지>[@버전]    npm 패키지 설치"
    echo "  $0 skill  <스킬-경로>            스킬 심볼릭 링크"
    echo ""
    echo "환경변수:"
    echo "  OPENCODE_AIDM_ROOT    설치 경로 (기본값: /opt/aidm)"
    exit 1
}

# ── 사전 검증 ───────────────────────────────────────────
if [ $# -lt 2 ]; then
    usage
fi

if [ ! -d "${AIDM_ROOT}" ]; then
    echo "[오류] ${AIDM_ROOT}가 존재하지 않습니다. setup.sh를 먼저 실행하세요."
    exit 1
fi

if [ ! -x "${NODE_DIR}/bin/node" ]; then
    echo "[오류] ${NODE_DIR}/bin/node가 없습니다. setup.sh를 먼저 실행하세요."
    exit 1
fi

COMMAND="$1"
TARGET="$2"

case "${COMMAND}" in
    plugin)
        echo "=== npm 패키지 설치: ${TARGET} ==="
        echo "경로: ${AIDM_ROOT}"

        NPM_ARGS=(install -g "${TARGET}" --prefix "${AIDM_ROOT}")

        if [ -f "${SYSTEM_CA_BUNDLE}" ]; then
            echo "CA 번들: ${SYSTEM_CA_BUNDLE}"
            sudo env PATH="${NODE_DIR}/bin:${PATH}" NODE_EXTRA_CA_CERTS="${SYSTEM_CA_BUNDLE}" \
                "${NODE_DIR}/bin/npm" "${NPM_ARGS[@]}"
        else
            echo "[경고] CA 번들 없음, strict-ssl=false 사용"
            sudo env PATH="${NODE_DIR}/bin:${PATH}" \
                "${NODE_DIR}/bin/npm" "${NPM_ARGS[@]}" --strict-ssl=false
        fi

        echo "설치 완료."
        ;;

    skill)
        echo "=== 스킬 링크: ${TARGET} ==="

        # 절대 경로로 변환
        SKILL_PATH="$(cd "$(dirname "${TARGET}")" && pwd)/$(basename "${TARGET}")"

        if [ ! -f "${SKILL_PATH}/SKILL.md" ]; then
            echo "[오류] ${SKILL_PATH}/SKILL.md가 없습니다. 유효한 스킬 디렉토리가 아닙니다."
            exit 1
        fi

        SKILL_NAME="$(basename "${SKILL_PATH}")"
        LINK_PATH="${SKILLS_DIR}/${SKILL_NAME}"

        if [ -e "${LINK_PATH}" ]; then
            echo "[경고] ${LINK_PATH}가 이미 존재합니다. 건너뜀."
            exit 0
        fi

        sudo mkdir -p "${SKILLS_DIR}"
        sudo ln -s "${SKILL_PATH}" "${LINK_PATH}"
        echo "링크 완료: ${LINK_PATH} -> ${SKILL_PATH}"
        ;;

    *)
        echo "[오류] 알 수 없는 명령: ${COMMAND}"
        usage
        ;;
esac
