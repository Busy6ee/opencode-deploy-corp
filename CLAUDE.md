# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

사내 프록시 기반 보안망에서 **OpenCode**(오픈소스 AI 코딩 에이전트)를 온프레미스 운영하기 위한 배포/설정 관리 저장소. 조직 공용 스킬과 설정 템플릿을 관리하며, 각 서버의 `/opt/aidm/`에 배포한다.

## 저장소 구조

- `setup.sh` — 대화형 서버 셋업 스크립트. Node.js 설치, OpenCode npm 설치, `opencode.jsonc` 생성, 환경 스크립트(`opencode.sh`) 생성을 자동화한다.
- `AGENTS.md` — AI 에이전트 행동 규칙 및 온프레미스 정책 정의 (읽기 전용, 사람만 수정).
- `skills/` — 공용 스킬 디렉토리 (향후 추가). 각 스킬은 `SKILL.md` + `references/`로 구성.
- `configs/` — 설정 템플릿 디렉토리 (향후 추가).

## 핵심 제약

- **모든 외부 아웃바운드 트래픽은 기본 차단**. 허용 여부를 판단하는 방식.
- 환경변수 7종(`OPENCODE_DISABLE_*`)이 반드시 `true`로 설정되어야 한다.
- provider `baseURL`은 사내 서버 주소만 허용. 외부 URL 금지.
- 로컬 MCP만 허용. 원격 MCP URL 등록 금지.
- 프로덕션 설정 파일 직접 수정 금지 — 템플릿(`configs/`)을 수정하고 배포를 제안한다.
- `.env`에 실제 크레덴셜이나 서버 IP를 하드코딩하지 않는다.

## 에이전트 수정 범위

| 수정 가능 | `skills/*/SKILL.md`, `skills/*/references/*`, `configs/` 내 템플릿, `docs/plans/*` |
|-----------|---|
| 읽기 전용 | `.env.template`, 배포 스크립트(`setup.sh`), 프로파일 스크립트 템플릿 |
| 사람 전용 | `AGENTS.md`, 프로덕션 `.env`, `/opt/aidm/` 내 실제 설정 |

## 커밋 및 스타일

- 한국어로 작성한다.
- 이모지를 사용하지 않는다.
- 코드 블록에 언어 태그를 명시한다.
- 커밋 메시지는 한국어, 간결하게 작성한다.

## 스킬 설계 기준

- **자기 완결성**: 저장소 루트 상대 경로에 의존하지 않으며, `references/`에 필요한 컨텍스트를 자체 포함.
- **라우터-참조 분리**: SKILL.md가 300줄 초과 시 라우터 패턴으로 전환 (SKILL.md는 100줄 이내 라우터, 상세는 `references/`).
- SKILL.md 500줄 이하, 한국어, 지시형 스타일(`IF ... THEN ...`).
- 신규 도구는 **분석 → 가이드 → 스킬** 순서. 스킬은 명시 요청 시에만 생성.

## 배포 대상 경로

```
/opt/aidm/
├── bin/opencode
├── node/              # Node.js 바이너리 (setup.sh가 설치)
├── config/
│   ├── opencode.jsonc # 공용 설정
│   └── skills/        # 공용 스킬
└── opencode.sh        # 환경 스크립트
```
