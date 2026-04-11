# OpenCode 온프레미스 배포

사내 프록시 기반 보안망에서 [OpenCode](https://github.com/nicepkg/opencode)를 온프레미스 운영하기 위한 배포/설정 관리 저장소.

## 구성

| 파일 | 역할 |
|------|------|
| `setup.sh` | 신규 서버 초기 셋업 (Node.js, OpenCode, 설정 파일, 환경 스크립트) |
| `install.sh` | 초기 설치 후 플러그인(npm 패키지)/스킬 추가 설치 |
| `AGENTS.md` | AI 에이전트 행동 규칙 및 온프레미스 정책 |

## 초기 설치

```bash
git clone <this-repo>
cd opencode-deploy-corp
./setup.sh
```

대화형으로 아래 항목을 입력받는다:

- 설치 경로 (기본값: `/opt/aidm`)
- 프로바이더 ID, 서버 주소
- 모델 ID, 컨텍스트/출력 제한
- OpenCode 버전 (기본값: latest)

설치 완료 후 환경 적용:

```bash
source /opt/aidm/opencode.sh
```

## 추가 설치

`setup.sh` 이후 플러그인이나 스킬을 공용 경로에 추가할 때 사용한다.

```bash
# npm 플러그인 설치
./install.sh plugin @ai-sdk/openai-compatible

# 특정 버전 설치
./install.sh plugin @ai-sdk/openai-compatible@0.2.0

# 스킬 심볼릭 링크
./install.sh skill /path/to/my-skill
```

`OPENCODE_AIDM_ROOT` 환경변수로 설치 경로를 지정한다 (기본값: `/opt/aidm`).
`opencode.sh`를 source한 상태라면 자동으로 설정된다.

## 디렉토리 구조 (서버)

```
/opt/aidm/                  # 설치 경로 (변경 가능)
├── bin/opencode            # OpenCode 바이너리
├── node/                   # Node.js (setup.sh가 설치)
├── config/
│   ├── opencode.jsonc      # 공용 설정
│   └── skills/             # 공용 스킬
├── opencode.sh             # 환경 스크립트 (source하여 사용)
└── lib/node_modules/       # npm 패키지
```

## 공용 vs 개인 설치

| | 공용 | 개인 |
|---|---|---|
| 경로 | `/opt/aidm/` | `~/.config/opencode/` |
| 설치 방법 | `install.sh` (sudo 필요) | 시스템 npm 자유 설치 |
| 권한 | 2750 (aidm 그룹 읽기+실행) | 사용자 소유 |
| 적용 범위 | aidm 그룹 전체 | 개인만 |

`opencode.sh`는 opencode 바이너리만 PATH에 추가하고 node/npm은 노출하지 않으므로, 개인 `npm install -g`는 시스템 npm을 사용하여 개인 경로에 설치된다.

## 온프레미스 정책

모든 외부 아웃바운드 트래픽은 기본 차단이다. `opencode.sh`에서 아래 환경변수를 설정한다:

- `OPENCODE_DISABLE_MODELS_FETCH`
- `OPENCODE_DISABLE_AUTOUPDATE`
- `OPENCODE_DISABLE_LSP_DOWNLOAD`
- `OPENCODE_DISABLE_EXTERNAL_SKILLS`
- `OPENCODE_DISABLE_SHARE`
- `OPENCODE_DISABLE_DEFAULT_PLUGINS`

설정 파일(`opencode.jsonc`)에서 `autoupdate: false`, `share: "disabled"`로 이중 차단한다.

상세 정책은 [AGENTS.md](AGENTS.md) 참고.
