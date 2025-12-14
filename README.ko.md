# Agent Council

**[English Version](./README.md)**

> 여러 AI Agent의 의견을 수집하고 종합하는 Claude Code 플러그인
> [Karpathy의 LLM Council](https://github.com/karpathy/llm-council)에서 영감을 받음

## 데모

https://github.com/user-attachments/assets/c550c473-00d2-4def-b7ba-654cc7643e9b

## 작동 방식

Agent Council은 AI 합의를 수집하기 위한 3단계 프로세스를 구현합니다:

**Stage 1: Initial Opinions (초기 의견 수집)**
설정된 모든 AI 에이전트가 동시에 질문을 받고 독립적으로 응답합니다.

**Stage 2: Response Collection (응답 수집)**
각 에이전트의 응답을 수집하여 포맷된 형태로 표시합니다.

**Stage 3: Chairman Synthesis (의장 종합)**
Claude가 의장으로서 모든 의견을 종합하여 공통점, 차이점, 컨텍스트를 기반으로 최종 추천을 제시합니다.

## 설치

### 방법 A: npx로 설치 (권장)

```bash
npx github:team-attention/agent-council
```

현재 프로젝트 디렉토리에 스킬 파일들이 복사됩니다.

### 방법 B: Claude Code 플러그인으로 설치

```bash
# 마켓플레이스 추가
/plugin marketplace add team-attention/agent-council

# 플러그인 설치
/plugin install agent-council@team-attention-plugins
```

### 2. Agent CLI 설치

기본 설정에 필요한 CLI:

```bash
# OpenAI Codex CLI
# https://github.com/openai/codex

# Google Gemini CLI
# https://github.com/google-gemini/gemini-cli
```

설치 확인:
```bash
codex --version
gemini --version
```

### 3. Council 멤버 설정 (선택사항)

`council.config.yaml`을 편집하여 council을 커스터마이즈:

```yaml
council:
  members:
    - name: codex
      command: "codex exec"
      emoji: "🤖"
      color: "BLUE"
      description: "OpenAI Codex - 코드 중심, 실용적 접근"

    - name: gemini
      command: "gemini"
      emoji: "💎"
      color: "GREEN"
      description: "Google Gemini - 넓은 지식, 다양한 관점"

    # 필요에 따라 에이전트 추가
    # - name: grok
    #   command: "grok"
    #   emoji: "🚀"
    #   color: "MAGENTA"
```

## 사용법

### Claude를 통한 사용

Claude에게 council 소집을 요청하면 됩니다:

```
"다른 AI들 의견도 들어보자"
"council 소집해줘"
"여러 관점에서 검토해줘"
"codex랑 gemini 의견 물어봐"
```

### 스크립트 직접 실행

```bash
./skills/agent-council/scripts/council.sh "질문 내용"
```

## 예시

```
User: "새 대시보드 프로젝트에 React vs Vue 어떨까? council 소집해줘"

Claude:
1. council.sh 실행하여 Codex와 Gemini 의견 수집
2. 각 에이전트의 관점 표시
3. 의장으로서 종합:
   "Council의 의견을 바탕으로, 대시보드의 데이터 시각화 요구사항과
   팀의 숙련도를 고려할 때..."
```

## 프로젝트 구조

```
agent-council/
├── .claude-plugin/
│   ├── plugin.json          # 플러그인 매니페스트
│   └── marketplace.json     # 마켓플레이스 설정
├── skills/
│   └── agent-council/
│       ├── SKILL.md         # 스킬 문서
│       └── scripts/
│           └── council.sh   # 실행 스크립트
├── council.config.yaml      # Council 멤버 설정
├── README.md                # 영어 문서
├── README.ko.md             # 이 문서
└── LICENSE
```

## 주의사항

- 각 에이전트 호출에 API 비용 발생
- 응답 시간은 가장 느린 에이전트에 의존 (병렬 실행)
- 민감한 정보는 council에 공유하지 않기
- 에이전트는 기본적으로 병렬로 실행되어 빠른 응답 제공

## 기여하기

기여를 환영합니다! 다음과 같은 기여가 가능합니다:
- 새로운 AI 에이전트 지원 추가
- 종합 프로세스 개선
- 설정 옵션 확장

## 라이선스

MIT 라이선스 - 자세한 내용은 [LICENSE](./LICENSE) 참조

## 크레딧

- [Karpathy의 LLM Council](https://github.com/karpathy/llm-council)에서 영감
- [Claude Code](https://claude.ai/code)용으로 제작
