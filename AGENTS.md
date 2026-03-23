# OpenCode 온프레미스 운영 -- Agent Instructions

이 저장소는 사내 프록시 기반 보안망에서 **OpenCode**(오픈소스 AI 코딩 에이전트)를 운영하고, 조직 공용 스킬을 관리한다.

## 운영 전제

- **개별 서버 설치**: 각 서버에 독립적으로 설치하며, 통일 경로 `/opt/aidm/`를 사용한다.
- **공용 스킬**: 이 레포가 원본 소스이며, 각 서버의 `/opt/aidm/config/skill/`에 배포한다.
- **아웃바운드 트래픽**: 모든 외부 통신은 기본 차단이다. 차단 여부가 아닌, 허용 여부를 판단한다.
- **프로바이더**: Ollama(단일 사용자/소규모) 또는 vLLM + Ray 클러스터(다중 사용자/대형 모델)를 사용한다.

---

## 파일 수정 범위

에이전트가 수정할 수 있는 영역을 명시적으로 제한한다.

| 영역 | 수정 주체 | 대상 |
|------|----------|------|
| **에이전트 수정** | AI 에이전트 | `skills/*/SKILL.md`, `skills/*/references/*`, `configs/` 내 템플릿, `docs/plans/*` |
| **읽기 전용** | 없음 (고정) | `.env.template`, 배포 스크립트, 프로파일 스크립트 템플릿 |
| **사람 수정** | 사람 전용 | `AGENTS.md`, 프로덕션 `.env`, `/opt/aidm/` 내 실제 설정, `/etc/profile.d/` |

### 금지 사항

- `/opt/aidm/config/opencode.jsonc` 등 프로덕션 설정 파일을 직접 수정하지 않는다. 템플릿(`configs/`)을 수정하고 배포를 제안한다.
- `.env` 파일에 실제 크레덴셜이나 서버 IP를 하드코딩하지 않는다.
- 프로파일 스크립트(`/etc/profile.d/aidm.sh`)를 직접 수정하지 않는다.

---

## 온프레미스 정책

### 필수 환경변수

모든 서버에서 아래 7종을 `true`로 설정해야 한다. 하나라도 누락되면 외부 트래픽이 발생한다.

| 변수 | 차단 대상 |
|------|----------|
| `OPENCODE_DISABLE_MODELS_FETCH` | 모델 목록 갱신 (`models.dev`, 60분 주기) |
| `OPENCODE_DISABLE_AUTOUPDATE` | 자동 업데이트 (GitHub API, npm) |
| `OPENCODE_DISABLE_LSP_DOWNLOAD` | LSP 서버 자동 다운로드 |
| `OPENCODE_DISABLE_EXTERNAL_SKILLS` | 외부 스킬 다운로드 |
| `OPENCODE_DISABLE_SHARE` | 세션 공유 (`opncd.ai`) |
| `OPENCODE_DISABLE_DEFAULT_PLUGINS` | 번들 플러그인 로드 |
| `OPENCODE_DISABLE_CLAUDE_CODE` | Claude Code 시스템 비활성화 |

설정 파일을 생성하거나 수정할 때 반드시 이 7종이 포함되었는지 확인한다.

### 아웃바운드 트래픽 분류

분석 시 모든 외부 통신을 세 범주로 나눈다:

| 범주 | 정의 | 대응 |
|------|------|------|
| **무조건 발생** | 시작 시 자동 실행 (자동 업데이트, 텔레메트리) | 환경변수/설정으로 반드시 차단 |
| **사용자 트리거** | 특정 기능 사용 시 발생 (검색, OAuth) | 해당 기능 미사용/미설정으로 방지 |
| **조건부** | 외부 서비스 설정 시에만 발생 (MCP 원격, 웹훅) | 설정하지 않으면 자동 방지 |

핵심: "모든 아웃바운드를 막아야 한다"가 아니라, **어떤 것이 치명적이고 어떤 것이 무해한지** 구분한다.

### 이중 차단 원칙

핵심 항목(자동 업데이트, 세션 공유)은 환경변수 **+** 설정 파일 양쪽에서 차단한다:

```jsonc
{
  "autoupdate": false,
  "share": "disabled"
}
```

환경변수는 `/etc/profile.d/aidm.sh`로 중앙 관리하고, 설정 파일은 `opencode.jsonc`에서 이중으로 건다.

### 프로바이더 설정

- Provider는 `@ai-sdk/openai-compatible` npm 어댑터를 사용한다.
- `baseURL`은 반드시 사내 서버 주소만 지정한다. 외부 URL 금지.
- `models.dev` 자동 로드가 비활성화되므로 모델별 `name`과 `limit`(context, output)을 명시한다.
- Speculative decoding(MTP) 활성화 시 JSON 구조화 출력이 깨진다. Tool call 등 구조화된 응답이 필요하면 반드시 비활성화한다.

```jsonc
{
  "provider": {
    "ollama": {
      "npm": "@ai-sdk/openai-compatible",
      "options": { "baseURL": "http://<OLLAMA_HOST>:11434/v1" },
      "models": {
        "qwen2.5-coder:32b": {
          "name": "Qwen 2.5 Coder 32B",
          "limit": { "context": 32768, "output": 8192 }
        }
      }
    }
  }
}
```

### 설정 우선순위

낮은 순서부터: remote `.well-known` < 전역(`~/.config/opencode/`) < 커스텀(`OPENCODE_CONFIG`) < 프로젝트 루트 < `.opencode/` < 인라인(`OPENCODE_CONFIG_CONTENT`) < 관리형(`OPENCODE_CONFIG_DIR`).

`OPENCODE_CONFIG_DIR=/opt/aidm/config`이 최고 우선순위이므로, 여기에 배치한 설정이 모든 개인 설정을 덮어쓴다.

---

## 공용 스킬 관리

### Analysis-First 흐름

새로운 도구를 바로 스킬화하지 않는다. 반드시 아래 순서를 따른다:

1. **분석** -- 아웃바운드 트래픽 전수 조사, 차단 메커니즘 도출
2. **가이드 작성** -- 사람이 읽을 수 있는 단계별 설명
3. **스킬 작성** -- 반복 배포가 확인된 경우, **명시 요청 시에만** 생성

모든 도구가 스킬화할 만큼 반복 사용되지는 않는다. 분석 리포트만으로 충분한 경우가 많다.

### 스킬 디렉토리 구조

```
skills/
├── setup-<product>-onprem/       # 셋업 스킬
│   ├── SKILL.md                  # 지시형, 조건-행동 구조
│   └── references/               # 번들 참조 문서
│       ├── guide.md              # 원본 가이드 발췌
│       └── config.jsonc          # 샘플 설정
└── analyze-onprem-readiness/     # 분석형 스킬
    └── SKILL.md
```

### 스킬 vs 가이드 역할

| | 가이드 | 스킬 (SKILL.md) |
|---|---|---|
| 대상 | 사람 (관리자, 개발자) | AI 에이전트 |
| 형식 | 단계별 설명, 배경 포함 | 지시형, 조건-행동 구조 |
| 위치 | `<product>-onpremise-guide/` | `skills/<skill-name>/` |
| 갱신 | 도구 버전 변경 시 | 가이드 변경 시 references 동기화 |

### 배포 경로

1. **개발**: 이 레포의 `skills/` 디렉토리에서 작성/수정
2. **테스트**: 로컬에서 `skills.paths`로 이 레포의 `skills/`를 지정하여 검증
3. **배포**: 각 서버의 `/opt/aidm/config/skill/`에 동기화
4. **로딩**: `OPENCODE_CONFIG_DIR/skill/`은 OpenCode가 자동 스캔한다

동기화 방법:

```bash
# 이 레포를 각 서버에 clone
git clone <this-repo> /opt/aidm/src/opencode-deploy-corp

# skills를 config/skill/에 심볼릭 링크
ln -s /opt/aidm/src/opencode-deploy-corp/skills/* /opt/aidm/config/skill/

# 업데이트 시
cd /opt/aidm/src/opencode-deploy-corp && git pull
```

---

## 스킬 설계 기준

### 자기 완결성

- 스킬은 **저장소 루트 상대 경로에 의존하지 않는다**.
- `references/`에 필요한 컨텍스트를 자체 포함하여, 어디에 설치해도 동작해야 한다.
- 외부 URL이나 원격 리소스를 참조하지 않는다.

### 라우터-참조 분리 패턴

SKILL.md가 300줄을 넘기거나 다수의 독립 도메인을 포함하면, 라우터 패턴으로 전환한다:

```
<skill-name>/
├── SKILL.md                  # 라우터 (100줄 이내)
│                               트리거 조건 + 섹션 인덱스 + 라우팅 규칙
└── references/
    ├── 01-<domain-a>.md      # 도메인별 참조 문서
    └── 02-<domain-b>.md
```

- SKILL.md는 질문 유형에 따라 **어떤 참조 파일을 읽을지 지시하는 라우터** 역할만 한다.
- 300줄 이상의 참조 파일에는 목차를 포함한다.

### SKILL.md 작성 규칙

- 지시형 스타일: 설명이 아닌 지시 (`IF ... THEN ...`)
- 500줄 이하 (초과 시 라우터 패턴 적용)
- 한국어 작성
- 코드 블록에 언어 태그 명시
- 불필요한 이모지 사용하지 않음

---

## 개별 서버 배포

### 디렉토리 구조

모든 서버에서 동일한 경로를 사용한다:

```
/opt/aidm/
├── bin/opencode              # npm prefix 설치
├── lib/node_modules/         # npm 패키지
├── config/
│   ├── opencode.jsonc        # 공용 설정
│   └── skill/                # 공용 스킬
│       ├── setup-opencode-onprem/
│       ├── setup-crush-onprem/
│       └── analyze-onprem-readiness/
├── src/                      # 소스 레포 clone
│   └── opencode-deploy-corp/ # 이 레포
└── aidm.sh                   # 프로파일 스크립트
```

### 설치 절차

```bash
# 1. OpenCode 설치
npm install -g opencode-ai --prefix /opt/aidm

# 2. 이 레포 clone
git clone <this-repo> /opt/aidm/src/opencode-deploy-corp

# 3. 설정 배치
mkdir -p /opt/aidm/config/skill
cp /opt/aidm/src/opencode-deploy-corp/configs/opencode.jsonc /opt/aidm/config/

# 4. 스킬 심볼릭 링크
ln -s /opt/aidm/src/opencode-deploy-corp/skills/* /opt/aidm/config/skill/

# 5. 프로파일 스크립트 연결
sudo ln -s /opt/aidm/aidm.sh /etc/profile.d/aidm.sh
```

### 프로파일 스크립트

```bash
#!/bin/bash
# /opt/aidm/aidm.sh

export PATH="/opt/aidm/bin:$PATH"
export OPENCODE_CONFIG_DIR="/opt/aidm/config"

# 아웃바운드 차단
export OPENCODE_DISABLE_MODELS_FETCH=true
export OPENCODE_DISABLE_AUTOUPDATE=true
export OPENCODE_DISABLE_LSP_DOWNLOAD=true
export OPENCODE_DISABLE_EXTERNAL_SKILLS=true
export OPENCODE_DISABLE_SHARE=true
export OPENCODE_DISABLE_DEFAULT_PLUGINS=true
# export OPENCODE_DISABLE_CLAUDE_CODE=true  # 필요 시 활성화
```

프로파일 스크립트 연결 시 NFS 지연 안전 패턴 사용:

```bash
# /etc/profile.d/aidm.sh
[ -f /opt/aidm/aidm.sh ] && source /opt/aidm/aidm.sh
```

---

## 도구 연동

### Ollama

- `@ai-sdk/openai-compatible` provider로 등록
- `baseURL`: `http://<OLLAMA_HOST>:11434/v1`
- 원격 접속 허용: `OLLAMA_HOST=0.0.0.0:11434 ollama serve`
- 연결 확인: `curl http://<GPU서버IP>:11434/v1/models`

### vLLM + Ray 클러스터

다중 사용자, 대형 모델(70B+), 배치 추론이 필요한 경우:

- Head 서버: Ray Head + vLLM(GPU) + Ollama(CPU) + Nginx
- Worker 서버: Ray Worker + GPU
- Nginx에서 SSE 스트리밍 지원 (buffering off, 600s timeout)
- Speculative decoding은 JSON 구조화 출력과 비호환 -- 비활성화 필요

### MCP 서버

- **로컬 MCP만 허용한다.** 원격 MCP URL을 설정에 등록하지 않는다.
- Oh My OpenCode 사용 시 기본 활성화된 원격 MCP(librarian 등)를 반드시 비활성화한다.

---

## 품질 게이트

### 스킬 배포 전

1. 자기 완결성: 저장소 외부 경로 참조 없음
2. 외부 URL 또는 아웃바운드 트리거 없음
3. `references/`에 필요한 컨텍스트 모두 포함
4. SKILL.md 500줄 이하
5. 한국어, 코드 블록 언어 태그, 이모지 없음

### 설정 배포 전

1. 환경변수 7종 전부 `true`로 설정됨
2. provider `baseURL`에 외부 URL 없음
3. 원격 MCP 서버 등록 없음
4. 모델별 `limit` (context, output) 명시됨
5. `share: "disabled"`, `autoupdate: false`
6. `$schema` 필드는 사내 호스팅 URL이거나 제거됨

### 신규 도구 분석

1. 아웃바운드 트래픽 전수 조사 (3분류: 무조건/사용자트리거/조건부)
2. 차단 메커니즘 파악 (환경변수, 설정 파일, 코드 패치, 제로 설정)
3. 비치명적 트래픽과 치명적 트래픽 구분
4. 가이드 문서 먼저 작성, 스킬은 명시 요청 시에만

---

## 검증 완료 도구

| 도구 | 분석 | 가이드 | 스킬 | 비고 |
|------|:----:|:------:|:----:|------|
| OpenCode | O | O | O | 환경변수 7종 차단 |
| Oh My OpenCode | O | O | O | MCP 3개 + librarian 차단 |
| Crush | O | O | O | 전역 설정/스킬/규칙 |
| AionUi | O | O | O | Electron, 텔레메트리 분석 |
| llmfit | O | O | - | 제로 아웃바운드, 스킬 불필요 |
| vllm-docker-corp | O | O | - | Ray 다중 GPU 클러스터 |
| OpenClaw | O | - | - | 설정만으로 완전 차단 가능 |
| Entire CLI | O | - | - | 텔레메트리 OFF만으로 운용 |

---

## 커밋 및 스타일

- 한국어로 작성한다.
- 이모지를 사용하지 않는다.
- 코드 블록에 언어 태그를 명시한다.
- `.env` 파일에 실제 크레덴셜, 서버 IP를 커밋하지 않는다. 템플릿(`.env.template`)만 커밋한다.
- 커밋 메시지는 한국어, 간결하게 작성한다.
