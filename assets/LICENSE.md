# 에셋 출처

## NanumMiNiSonGeurSsi.ttf — 나눔손글씨 미니 손글씨

네이버가 배포하는 나눔손글씨 글꼴. 개인·기업 상업적 이용을 포함해 자유롭게 쓸 수 있고
재배포도 허용된다. 글꼴 자체를 유료로 판매하는 것만 금지된다.

- 출처: https://hangeul.naver.com/font
- 앱은 이 파일을 번들에 넣고 프로세스 범위로만 등록한다(`CTFontManagerRegisterFontsForURL`).
  시스템에 설치하지 않으므로 다른 앱에 영향을 주지 않는다.

## spritesheet.webp — 레토

`hatch-pet` 스킬(Apache-2.0)로 만든 8×11 아틀라스에서 출발했다. 원본 캐릭터는 luxia yoon 의 랙돌 고양이 레토(Retto).

- 2026-08-27: 시선 행 10 의 크기 드리프트를 `tools/sprite-scale.swift` 로 교정했다.
- 2026-08-27: 자는 행(행 11)을 `tools/sprite-sleep.swift` 로 만들어 붙였다. 새로 그린 것이 아니라
  대기 행의 눈 감은 프레임을 재료로 숨쉬기·고개 기울임을 코드로 넣은 것이다.
  아틀라스는 `1536×2496`, 8×12 그리드, 무손실 VP8L(`cwebp -lossless`).
- 2026-08-28: 행 11을 luxia yoon이 제공한 레토 사진을 참고해 OpenAI 내장 이미지 생성으로
  만든 누운 수면 6프레임으로 교체했다. 아틀라스 규격과 무손실 WebP 형식은 유지한다.

## icon.png

앱 아이콘. 위 스프라이트에서 잘라 만들었다.
