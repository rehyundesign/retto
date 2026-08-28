# 꿀벌 스킨

리락쿠마와 달리 특정 캐릭터가 아니라 그냥 꿀벌 옷이다. 상표 문제가 없어 배포에 포함한다
(`assets/spritesheet-bee.webp` 는 레포에 커밋된다).

## 어떻게 만들었나

옷은 자세마다 형태가 달라져 레이어 합성이 안 된다. 자세 묶음마다 기본 아틀라스 칸을
격자에 넣고 한 번에 입혔다 — 한 장 안에서 만들어야 옷이 칸마다 안 달라진다.

| 생성 | 행 | 칸 |
|---|---|---|
| `gen-idle` | 0 | 7 |
| `gen-run` | 1 | 8 · 행 2 는 좌우 반전 |
| `gen-wave` | 3·4 | 9 |
| `gen-sit` | 6·7 | 12 |
| `gen-fail` | 5 | 8 |
| `gen-sleep` | 8·11 | 12 |
| `gen-gaze9` `gen-gaze10` | 9·10 | 16 |

되돌릴 때는 원래 칸의 발 폭·발 중앙·바닥선에 맞춘다(`dress.py`). 달리는 행만은 발이 떠 있어
bbox 높이로 맞춘다. 머리가 칸 위로 넘치면 그 칸만 줄인다.

마지막에 `../rilakkuma-skin/clean-strays.py` 로 가장자리 조각을 지운다 — 격자를 자를 때
옆 칸이 얇게 걸려 들어온다.

## 파일

- `idle-source.png` `idle-alpha.png` — 옷 기준이 된 첫 장
- `gen-*.png` — 자세 묶음별 생성 원본 (크로마키 `#0369F3`)
- `atlas.png` — 완성 아틀라스 PNG
- `costume-prompt.txt` `dress.py` — 생성·되돌리기 도구

## 다시 구울 때

```sh
python3 ../rilakkuma-skin/clean-strays.py atlas-raw.png atlas.png
cwebp -lossless -exact -z 9 atlas.png -o ../../assets/spritesheet-bee.webp
```
