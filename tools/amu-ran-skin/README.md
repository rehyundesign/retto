# 아무 · 란

기본 레토의 얼굴·파란 눈·체형을 유지한 교복과 하트 변신 스킨이다. 평소에는 교복을 입고, 완료(`waving`)와 점프(`jumping`)에서 변신한다. 란은 레토의 동작과 같은 포즈 시계를 사용해 응원·손 맞추기·기다리기·잠자기에 반응한다.

- 기본 대기, 양방향 드래그, 완료, 점프, 실패, 입력 대기, 작업, 도구 사용, 수면의 10개 동작에 독립 그림 16장씩 사용한다.
- 교복과 변신 시선은 각각 16방향의 전체 캐릭터 원본이다. 머리를 잘라 움직이지 않는다.
- 앞뒤 효과는 8초 주기의 독립 시계로 재생한다. 시선 고정 중에도 하트·반짝임과 란의 호흡은 계속 움직인다.
- 네이티브 리소스는 캐릭터 160장, 시선 32장, 앞뒤 효과 1600장, 란 32장, 상호작용 설정 1개다. 16열 아틀라스는 캐릭터와 시선만 포함한다.
- 기본 동작 3.2초, 드래그 1.6초, 완료·점프·작업 2.4초, 수면 6.4초의 승인된 속도를 사용한다.

## 검증 및 미리보기

Python 스크립트에는 Pillow와 NumPy가 필요하다. 새 의존성 설치나 잠금 파일 변경은 포함하지 않는다.

```sh
python3 tools/amu-ran-skin/validate-all.py
python3 tools/amu-ran-skin/effects/validate.py
python3 tools/amu-ran-skin/effects/verify-visibility.py
zsh tools/amu-ran-skin/native/build-review.sh
# 마지막 명령이 출력한 임시 폴더로 실제 RettoView 렌더를 확인한다.
python3 tools/amu-ran-skin/native/verify-render.py /path/to/retto-amu-review
python3 tools/amu-ran-skin/serve-preview.py --port 8773
```

`preview-full.html?effects=heart3`는 상태 이름·설명, 재생·속도, 밝은/어두운 배경, 효과 숨기기, 캐릭터 고정, 의상별 시선 검토를 제공한다. 원본·변형·합성·검증 기록은 제작 이력으로 함께 보존한다. 예전 후보나 검토용 스트립을 생산 아틀라스로 잘라 쓰지 않는다.

`effects/approved-character-lock.json`은 승인된 캐릭터·시선·란 224장과 아틀라스의 해시를 고정한다. `effects/baseline-v2/`의 6장으로 효과 가시성을 비교하므로 별도 미게시 Git 이력이 필요하지 않다. 시선 등록 기록의 절대 경로는 원래 생성 위치의 이력이며, 검증기는 현재 체크아웃의 상대 경로로 소스를 읽는다.

## 앱 통합과 로컬 설치

`macos/Sources/AmuRan*.swift`와 기존 메뉴·프레임·시선 매핑에 추가된 분기는 아무·란에만 적용한다. 하나·토토, 잔느·핀, 쇼콜라 하트, 피치핏치의 코드와 리소스는 유지한다. `macos/scripts/build.sh`는 아무·란 아틀라스와 개별 셀을 번들에 포함한다.

`native/build-local-integration.py`는 현재 소스로 설치 후보를 만들면서 기존 로컬 앱의 다른 스킨 리소스를 복사하고 해시를 확인한다. 이 도구는 설치하거나 앱을 재시작하지 않는다. 설치는 사용자가 요청한 경우에 수행한다.

2026-10-29 로컬 설치는 별도로 승인받아 완료했다. 기존 리소스 11178개를 보존했고, 통합 네이티브 렌더 164장이 승인된 렌더와 픽셀 단위로 일치했다. 설치본 자체 검사에서 `ok`, `skinsOK`, `assetOK` 및 아무·란 시계 검사를 통과했고 메뉴와 저장값 `amuRan`을 확인했다. 자세한 당시 기록은 `native/installation.json`에 있다. 이 기록은 다른 기기의 설치 상태를 보장하지 않는다.
