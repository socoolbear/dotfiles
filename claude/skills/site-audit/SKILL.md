---
name: site-audit
description: 웹사이트의 기술적 성능, SEO, AEO 요소를 Lighthouse 와 Playwright 로 종합 진단합니다. "웹사이트 평가해줘", "SEO 체크해줘", "사이트 성능 점검", "AEO 진단" 같이 특정 URL 의 성능·검색최적화 점검을 요청할 때 사용.
---

# 웹사이트 종합 진단 (성능 · SEO · AEO)

대상 사이트의 기술적 성능, 검색 엔진 최적화(SEO), 답변 엔진 최적화(AEO)를 진단합니다.
사용자에게 받은 URL 을 `$URL` 로 두고 아래 순서로 수행하세요.

## 1. Lighthouse 로 성능·SEO 지표 수집

```bash
npx lighthouse "$URL" --output json --output-path ./report.json --quiet --chrome-flags="--headless"
```

- `npx` 가 없거나 Chrome 헤드리스가 실패하면 사용자에게 Node/Chrome 설치 여부를 확인하세요.
- 산출물은 `./report.json` 입니다.

## 2. report.json 에서 핵심 지표 추출

`jq` 로 점수와 개선 대상 자산을 뽑아냅니다.

```bash
jq '{
  performance: .categories.performance.score,
  seo: .categories.seo.score,
  lcp: .audits["largest-contentful-paint"].displayValue,
  cls: .audits["cumulative-layout-shift"].displayValue,
  modern_image: .audits["modern-image-formats"].details.overallSavingsBytes,
  caching: .audits["uses-long-cache-ttl"].details.overallSavingsMs
}' report.json
```

- LCP / CLS 등 Core Web Vitals 와 SEO 점수를 정리하세요.
- 개선이 필요한 자산(차세대 이미지 포맷, 캐싱 TTL, 미사용 JS/CSS 등)을 목록화하세요.

## 3. HTML 소스로 AEO 관점 점검

대상 페이지의 HTML 을 확인해 다음을 파악하고 리포트에 반영하세요.

- **JSON-LD 구조화 데이터** 포함 여부 (`<script type="application/ld+json">`) 와 스키마 타입 (`Article`, `FAQPage`, `Organization` 등)
- **시맨틱 태그** 적절성 (`<article>`, `<header>`, `<main>`, `<nav>`, `<section>`)
- 메타 태그 (`title`, `meta description`, `og:*`) 와 제목 계층(`h1` 단일성)

HTML 확보 방법(택1):
- 정적 페이지: `curl -sL "$URL"` 후 `rg` 로 패턴 검색
- JS 렌더링 페이지: Playwright MCP (`browser_navigate` → `browser_snapshot` / `browser_evaluate`) 로 렌더링 후 DOM 확인

## 4. 종합 리포트 작성

세 영역을 하나의 리포트로 정리하세요.

1. **성능**: Lighthouse 점수, LCP/CLS, 우선 개선 자산
2. **SEO**: SEO 점수, 메타/제목/링크 이슈
3. **AEO**: 구조화 데이터·시맨틱 태그 충족도와 답변 엔진 노출 개선안

각 항목은 현재 상태 → 문제점 → 구체적 개선 액션 순으로 제시하세요.
