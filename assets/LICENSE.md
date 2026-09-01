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

## 스킨 아틀라스 — spritesheet-bee · spritesheet-luna · spritesheet-angel

기본 아틀라스(`spritesheet.webp`)의 레토를 재료로 만든 파생 아틀라스다. 규격·그리드·무손실
WebP 는 기본과 같고, 발바닥 메뉴 **스킨** 이 갈아 끼운다. 셋 다 레포와 배포 묶음에 넣는다.

**특정 캐릭터를 옮긴 것이 없다.** 가져온 것은 누구의 것도 아닌 차림새 셋이다.

| 파일 | 무엇을 입혔나 | 어떻게 |
| --- | --- | --- |
| `spritesheet-bee.webp` | 꿀벌 — 곤충 그 자체 | 자세 묶음마다 격자에 넣고 한 번에 옷을 입혔다 (`tools/bee-skin/dress.py`) |
| `spritesheet-luna.webp` | 마법소녀풍 달 요정 — 장르의 차림새 | 옷이 아니라 몸 색을 바꾼다. 크로마키를 초록으로 쓴 이유는 `tools/luna-skin/README.md` |
| `spritesheet-angel.webp` | 천사 날개 — 도상 그 자체 | 날개 PNG 세 장(`tools/angel-skin/wings/`)을 자세별로 합성 (`tools/angel-skin/build.py`) |

꿀벌·천사 날개·마법소녀는 어느 작품에도 속하지 않는 일반 도상이라 배포에 포함한다.
반대로 **리락쿠마 스킨은 남의 캐릭터**라서 만든 사람 기기에서만 쓴다 — 아틀라스를 레포에
넣지 않고(`.gitignore`), `build.sh` 가 배포 묶음에서도 빼며, 받아 간 쪽 메뉴에는 자물쇠로만
보인다(`SkinKind.isPersonal`).

## icon.png

앱 아이콘. 위 스프라이트에서 잘라 만들었다.
