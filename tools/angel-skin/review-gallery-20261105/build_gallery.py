"""Build a local angel-motion gallery without altering any source GIF."""
from pathlib import Path
from io import BytesIO
import base64
import hashlib
import json
import os
from urllib.parse import quote
from PIL import Image

ROOT = Path(__file__).resolve().parent
MOTION = ROOT.parent / 'motion'
NIGHT = MOTION / 'night-effects-v1-20261105'
MATTE = MOTION / 'matte-repair-v3-holes-20261105'
PET_EFFECTS = MOTION / 'pet-effects-v2-clean-idle-20261106'
PET_PREVIOUS = MOTION / 'pet-effects-v1-20261106'
ITEMS = [
    ('idle', '기본 대기', 'idle-v2-20261105', '확인한 버전', 'selected',
     '노란 별을 주고받으며, 날개와 빛·깃털이 흐르는 기본 동작.'),
    ('running', '작업 중 · 오르골 감상', 'running-v3-proportion-20261105', '비율 수정 · 검토용', 'review',
     '셋이 공중에 떠서 오르골을 감상해요. 레토는 두 앞발로 받치고, 돔 안의 두 수정 기둥이 회전하며 빛나요.'),
    ('running', '작업 중 · 오르골 비율 수정 전', 'running-v2-musicbox-20261105', '비율 수정 전', 'archive',
     '몸이 길고 펫의 상대 크기가 맞지 않아 교체한 이전 오르골 시안이에요.'),
    ('running', '작업 중 · 이전 날갯짓', 'running-v1-20261105', '교체 전 시안', 'archive',
     '오르골 감상으로 교체하기 전의 날갯짓 동작이에요.'),
    ('waiting', '입력 대기', 'waiting-v1-20261105', '검토용', 'review',
     '타토와 멜로디가 함께 손짓하고, 레토는 고개를 기울이며 기다려요.'),
    ('failed', '실패 · 위로', 'failed-v1-20261105', '검토용', 'review',
     '잠깐 멈칫한 레토를 두 펫이 토닥이고, 레토가 편안하게 회복해요.'),
    ('waving', '작업 완료', 'waving-v1-20261105', '검토용', 'review',
     '레토가 앞발로 인사하며 날개를 펼치고, 두 펫이 함께 축하해요.'),
    ('jumping', '클릭 · 다 같이 점프 & 윙크', 'jumping-v3-wink-20261105', '윙크 수정 · 검토용', 'review',
     '셋이 함께 날아오르며 같은 쪽 눈으로 윙크해요. 착지 후에는 편안하게 눈을 떠요.'),
    ('jumping', '클릭 · 표정 수정 전', 'jumping-v2-trio-flight-20261105', '표정 수정 전', 'archive',
     '다 함께 윙크하도록 눈매를 수정하기 전의 모션이에요.'),
    ('jumping', '클릭 · 이전 점프 초안', 'jumping-v1-20261105', '이전 미완성 초안', 'archive',
     '날개를 이용한 점프와 착지. 중간 4컷의 체형·발 위치 수정이 남아 있어요.'),
    ('sleeping', '수면 · 달빛 자장가', 'sleeping-v1-20261105', '새 수면 · 검토용', 'review',
     '셋이 나란히 웅크려 잠들어요. 느린 호흡에 접힌 날개와 꼬리가 살짝 움직이고, 초승달·별빛·작은 음표와 깃털이 흐릅니다.'),
    ('idle', '기본 대기 · 수정 전', 'idle-v1-20261105', '이전 시안', 'archive',
     '눈·귀·날개와 노란 별 피드백을 반영하기 전의 버전이에요.'),
]


def media(path):
    before = hashlib.sha256(path.read_bytes()).hexdigest()
    with Image.open(path) as im:
        frames = im.n_frames
        duration = 0
        im.seek(0)
        poster = im.convert('RGBA')
        poster.thumbnail((432, 432), Image.Resampling.LANCZOS)
        out = BytesIO()
        poster.save(out, format='PNG', optimize=True)
        for i in range(frames):
            im.seek(i)
            im.load()
            duration += im.info['duration']
        size = list(im.size)
    assert duration > 0 and frames > 1
    assert hashlib.sha256(path.read_bytes()).hexdigest() == before
    return {
        'src': quote(os.path.relpath(path, ROOT), safe='/.-') + '?v=' + before[:12],
        'transparent': path.suffix == '.webp',
        'poster': 'data:image/png;base64,' + base64.b64encode(out.getvalue()).decode(),
        'frames': frames, 'ms': duration, 'size': size, 'sha256': before,
    }


def main():
    data = []
    for state, title, folder, label, status, description in ITEMS:
        review = MOTION / folder / 'review'
        is_archive = status == 'archive'
        musicbox = folder in ('running-v2-musicbox-20261105','running-v3-proportion-20261105')
        trio_flight = folder in ('jumping-v2-trio-flight-20261105','jumping-v3-wink-20261105')
        direct = musicbox or trio_flight or folder == 'sleeping-v1-20261105'
        old_click = folder == 'jumping-v1-20261105' and is_archive
        effect = media(review/'night.webp') if direct else media(MATTE/state/'night.webp') if old_click else media(review / f'{state}.gif') if is_archive else media(MATTE/state/'night.webp')
        character = media(review/'character.webp') if direct else media(MATTE/state/'character.webp') if old_click else media(review / 'character.gif') if is_archive else media(MATTE/state/'character.webp')
        assert effect['ms'] == character['ms']
        motifs = {
            'idle': '노란 별을 주고받는 동작은 그대로, 밤빛과 가장자리 투명도를 적용했어요.',
            'running': description,
            'waiting': '두 펫의 손짓에 맞춰 양옆 별빛과 음표가 밝아지며 부르는 신호.',
            'failed': '토닥이는 동작 뒤에 흩어진 별빛과 음표가 다시 작은 별로 모여요.',
            'waving': '앞발 인사에 맞춰 달빛 아치와 별·음표가 펼쳐지는 피날레.',
            'jumping': description,
            'sleeping': description,
        }
        data.append({
            'id': folder if is_archive or direct else 'night-'+state, 'state': state, 'title': title,
            'label': label if is_archive or direct else '빈 공간 배경 제거',
            'status': status if is_archive or state == 'jumping' else 'review',
            'description': description if is_archive else motifs[state],
            'effect': effect, 'character': character,
            'next': '',
        })
        if musicbox and not is_archive:
            data.append({'id':'old-night-running','state':'running','title':'작업 중 · 이전 밤빛 효과',
                         'label':'교체 전 시안','status':'archive','description':'이전 날갯짓 동작의 밤빛 효과 버전이에요.',
                         'effect':media(NIGHT/state/'night.webp'),'character':media(NIGHT/state/'character.webp'),'next':''})
        if (not is_archive and not direct) or old_click:
            data.append({'id':'old-night-'+state,'state':state,'title':title+' · 배경 정리 전',
                         'label':'흰 테두리 수정 전','status':'archive','description':'흰 배경 테두리를 정리하기 전의 밤빛 효과 버전이에요.',
                         'effect':media(NIGHT/state/'night.webp'),'character':media(NIGHT/state/'character.webp'),'next':''})
            data.append({'id':folder+'-previous', 'state':state,
                         'title':title+' · 이전 효과', 'label':'이전 효과', 'status':'archive',
                         'description':description, 'effect':media(review/f'{state}.gif'),
                         'character':media(review/'character.gif'), 'next':''})
    pet_motifs = {
        'idle': '타토의 푸른 방울 파문·별빛, 멜로디의 장밋빛 하트·깃털이 별 놀이를 따라가요.',
        'running': '두 펫에게서 푸른 음표와 붉은 음표가 오르골 쪽으로 흘러요.',
        'waiting': '타토의 푸른 호출 파문과 멜로디의 붉은 하트 신호가 손짓에 맞춰 퍼져요.',
        'failed': '흩어진 청빛·장밋빛이 두 펫 곁으로 모이며 위로하는 잔광으로 가라앉아요.',
        'waving': '두 펫의 축하 동작에 푸른 별과 붉은 하트·깃털이 부채처럼 펼쳐져요.',
        'jumping': '타토는 푸른 별 궤적, 멜로디는 붉은 하트·깃털 궤적을 남기고 착지해요.',
        'sleeping': '두 펫의 호흡에 청빛·장밋빛 잔광이 은은하게 움직여요.',
    }
    before_pet = []
    pet_sources = json.loads((PET_EFFECTS/'render-inputs.json').read_text())
    old_pet_sources = json.loads((PET_PREVIOUS/'pre-edit-lock.json').read_text())
    for item in data:
        if item['status'] == 'archive':
            continue
        before_pet.append({**item, 'id':'before-pet-effects-'+item['state'],
                           'title':item['title']+' · 펫 효과 추가 전', 'status':'archive',
                           'label':'펫 효과 추가 전'})
        before_pet.append({**item, 'id':'pet-effects-v1-'+item['state'],
                           'title':item['title']+' · 타토 빛·흰 조각 수정 전', 'status':'archive',
                           'label':'타토 빛 수정 전', 'effect':media(PET_PREVIOUS/item['state']/'night.webp'),
                           'character':media(Path(old_pet_sources[item['state']]['character']))})
        item.update(id='pet-effects-'+item['state'], label='배경 조각 정리' if item['state']=='idle' else '푸른빛 강화',
                    description=item['description']+' '+pet_motifs[item['state']],
                    effect=media(PET_EFFECTS/item['state']/'night.webp'),
                    character=media(Path(pet_sources[item['state']]['character'])))
    data.extend(before_pet)
    for item in list(data):
        if item['state']=='idle' and item['status']!='archive':
            data.append({**item, 'id':'idle-before-airborne-regeneration',
                         'title':'기본 대기 · 재생성 전', 'status':'archive', 'label':'재생성 전'})
            prior_idle=MOTION/'idle-v3-airborne-20261106/review'
            data.append({**item, 'id':'idle-v3-tiny-eyes-rejected',
                         'title':'기본 대기 · 눈 비율 수정 전', 'status':'archive', 'label':'눈이 작아 교체',
                         'description':'공중 별놀이 모션은 유지하고, 지나치게 작아진 눈을 기본 비율로 수정하기 전 버전이에요.',
                         'effect':media(prior_idle/'night.webp'), 'character':media(prior_idle/'character.webp')})
            previous=MOTION/'idle-v4-base-eyes-20261106/review'
            data.append({**item, 'id':'idle-v4-eye-patch-rejected',
                         'title':'기본 대기 · 눈 주변 수정 시안', 'status':'archive', 'label':'정본 재생성 전',
                         'description':'눈 주변을 부분 수정했던 이전 시안이에요.',
                         'effect':media(previous/'night.webp'), 'character':media(previous/'character.webp')})
            fresh=MOTION/'idle-v5-canonical-20261106/review'
            item.update(id='idle-v5-canonical-20261106', title='기본 대기 · 공중 별놀이',
                        label='정본 캐릭터 재생성 · 검토용', status='review',
                        description='눈 크기와 흰자 조절 조건을 빼고 승인된 기본 레토 정본으로 캐릭터 전체를 다시 그렸어요. 별놀이 순서와 두 펫의 비행, 재생 속도는 유지했어요.',
                        effect=media(fresh/'night.webp'), character=media(fresh/'character.webp'))
    for item in list(data):
        if item['state']=='waiting' and item['status']!='archive':
            data.append({**item, 'id':'waiting-before-highfive-regeneration',
                         'title':'입력 대기 · 하이파이브 재생성 전', 'status':'archive', 'label':'이전 손짓 시안'})
            fresh=MOTION/'waiting-v2-highfive-20261106/review'
            item.update(id='waiting-v2-highfive-20261106', title='입력 대기 · 번갈아 하이파이브',
                        label='새 하이파이브 · 검토용', status='review',
                        description='살짝 웃는 레토가 공중의 타토, 멜로디와 차례로 하이파이브해요. 손바닥이 닿을 때 각각 푸른빛과 붉은빛이 반짝이고, 날개·귀·꼬리·리본이 동작을 따라 움직여요.',
                        effect=media(fresh/'night.webp'), character=media(fresh/'character.webp'))
    for item in list(data):
        if item['state']=='failed' and item['status']!='archive':
            data.append({**item, 'id':'failed-before-tears-regeneration',
                         'title':'실패 · 눈물 닦기 재생성 전', 'status':'archive', 'label':'이전 위로 시안'})
            fresh=MOTION/'failed-v2-tears-20261106/review'
            item.update(id='failed-v2-tears-20261106', title='실패 · 흑흑, 눈물 닦아주기',
                        label='새 눈물 모션 · 검토용', status='review',
                        description='셋이 함께 흑흑 울어요. 공중의 타토와 멜로디가 번갈아 레토의 볼에 흐르는 눈물을 닦아주고, 맑은 눈물 방울과 은은한 푸른빛·붉은빛이 이어져요.',
                        effect=media(fresh/'night.webp'), character=media(fresh/'character.webp'))
        elif item['state']=='running' and item['status']!='archive':
            data.append({**item, 'id':'running-before-dome-glow-enhancement',
                         'title':'작업 중 · 오르골 빛 보강 전', 'status':'archive', 'label':'돔 빛 보강 전'})
            item.update(id='running-v4-musicbox-glow-20261106', label='오르골 빛 보강 · 검토용',
                        description='기존 캐릭터와 오르골 회전 모션을 유지하고, 유리 돔 안에 은은한 오팔빛과 움직이는 반짝임을 더했어요. 돔 밖의 그림과 투명도는 그대로예요.',
                        effect=media(MOTION/'running-v4-musicbox-glow-20261106/review/night.webp'))
    for item in list(data):
        if item['state'] in ('waiting','failed') and item['status']!='archive':
            state=item['state']
            data.append({**item, 'id':state+'-before-stars-sad-effects',
                         'title':item['title']+' · 이펙트 보강 전', 'status':'archive', 'label':'이펙트 보강 전'})
            item.update(id='effect-repair-v3-'+state,
                        label='노란 별 보강 · 검토용' if state=='waiting' else '슬픈 이펙트 보강 · 검토용',
                        description='손바닥이 짝 닿는 순간 노란 다섯 꼭짓점 별이 퍼져요. 타토의 푸른빛과 멜로디의 붉은빛은 유지했어요.' if state=='waiting' else '눈물 방울을 더 또렷하게 하고, 쓸쓸한 푸른 달빛과 천천히 떨어지는 빗방울·깃털을 더했어요. 셋이 울고 눈물을 닦는 동작은 그대로예요.',
                        effect=media(MOTION/'effect-repair-v3-stars-sad-20261106'/state/'night.webp'))
    for item in list(data):
        if item['state']=='idle' and item['status']!='archive':
            data.append({**item, 'id':'idle-before-background-stars',
                         'title':'기본 대기 · 배경 별 보강 전', 'status':'archive', 'label':'배경 별 보강 전'})
            item.update(id='idle-v6-background-stars-20261106', label='배경 노란 별 · 검토용',
                        description='마음에 든 별놀이 동작은 그대로 두고, 캐릭터 뒤에 작은 노란 별들이 천천히 흐르며 서로 다른 타이밍으로 반짝이도록 더했어요. 가장자리는 부드럽게 투명해져요.',
                        effect=media(MOTION/'idle-v6-background-stars-20261106/review/night.webp'))
    for item in list(data):
        if item['state']=='failed' and item['status']!='archive':
            data.append({**item, 'id':'failed-before-pet-proportions',
                         'title':'실패 · 펫 크기 수정 전', 'status':'archive', 'label':'펫 크기 수정 전'})
            item.update(id='failed-v3-pet-proportions-20261106', label='펫 비율 수정 · 검토용',
                        description='타토와 멜로디의 크기를 다른 상태에 맞췄어요. 멜로디는 조금 더 작게, 눈물을 닦으러 다가와도 같은 크기를 유지해요. 기존 울음과 위로 동작·슬픈 이펙트는 이어집니다.',
                        character=media(MOTION/'failed-v3-pet-proportions-20261106/review/character.webp'),
                        effect=media(MOTION/'failed-v3-pet-proportions-20261106/review/night.webp'))
    for item in list(data):
        if item['state']=='jumping' and item['status']!='archive':
            data.append({**item, 'id':'jumping-before-tada',
                         'title':'클릭 · 따란 효과 보강 전', 'status':'archive', 'label':'따란 효과 보강 전'})
            item.update(id='jumping-v4-tada-20261106', label='따란 별빛 · 검토용',
                        description='셋이 함께 점프하고 윙크하는 순간 금빛 별과 빛줄기가 크게 퍼져요. 푸른빛·붉은빛이 양옆을 감싸고, 작은 노란 별들이 내려오며 착지해요.',
                        effect=media(MOTION/'jumping-v4-tada-20261106/review/night.webp'))
    for item in list(data):
        if item['state']=='running' and item['status']!='archive':
            data.append({**item, 'id':'running-before-floating-glints',
                         'title':'작업 중 · 빛·배경 반짝임 보강 전', 'status':'archive', 'label':'빛 보강 전'})
            item.update(id='running-v5-luminous-20261106', label='오르골·배경 반짝임 · 검토용',
                        description='유리 돔 안의 오팔빛과 반짝임을 더 또렷하게 했어요. 금빛·하늘빛·연보라 빛 알갱이가 주변에 천천히 떠다니고, 오르골 옆에서 위로 흐르는 반짝임도 더했어요.',
                        effect=media(MOTION/'running-v5-luminous-20261106/review/night.webp'))
    for item in list(data):
        if item['state']=='jumping' and item['status']!='archive':
            data.append({**item, 'id':'jumping-before-feather-mix',
                         'title':'클릭 · 별·깃털 혼합 전', 'status':'archive', 'label':'깃털 혼합 전'})
            item.update(id='jumping-v5-stars-feathers-20261106', label='별·깃털 따란 · 검토용',
                        description='셋이 함께 점프하고 윙크할 때 금빛 별과 하얀 깃털이 함께 퍼져요. 별은 반짝이고 깃털은 흔들리며 천천히 내려와요. 푸른빛·붉은빛은 그대로 살렸어요.',
                        effect=media(MOTION/'jumping-v5-stars-feathers-20261106/review/night.webp'))
    data.append({'id':'gaze-left-v1-20261106', 'state':'idle',
                 'title':'기본 대기 · 랜덤 별빛 놀이', 'status':'review', 'label':'기본 대기 랜덤 변형',
                 'description':'레토가 왼쪽으로 고개를 돌리면 타토가 별로 방향을 알려주고, 멜로디도 같은 쪽을 보며 앞발로 반응해요. 정면으로 자연스럽게 돌아오는 동작까지 새 전신 그림 16장으로 만들었어요.',
                 'next':'기본 대기에서 동작 한 바퀴마다 랜덤으로 선택해요. 좌우 드래그와 마우스 따라보기는 별도 동작입니다.',
                 'interaction':True, 'nativeInstalled':True,
                 'character':media(MOTION/'gaze-left-v1-20261106/review/character.webp'),
                 'effect':media(MOTION/'gaze-left-v1-20261106/review/night.webp')})
    for key,title,note in [
        ('drag-left','왼쪽 드래그 · 셋이 함께 비행','타토가 앞서며 별로 이끌고, 멜로디가 따라와요. 날개를 퍼덕이며 별빛과 깃털이 뒤로 흘러요.'),
        ('drag-right','오른쪽 드래그 · 셋이 함께 비행','멜로디가 앞서고 타토가 뒤따라요. 독립된 오른쪽 비행 그림 16장으로 구성했어요.'),
        ('gaze','마우스 360° 따라보기','마우스 상하좌우와 대각선 16방향을 따라봐요. 타토와 멜로디도 같은 방향으로 반응해요. 방향이 고정돼도 빛과 깃털은 계속 움직여요.')]:
        folder=MOTION/'interactions-v2-20261106'/key/'review'
        data.append({'id':'interactions-v2-'+key,'state':'gaze' if key=='gaze' else 'drag',
            'title':title,'status':'review','label':'상호작용 · 전신 그림 16장',
            'description':note,'next':'마우스로 직접 따라보기: 상호작용 미리보기에서 확인해요.',
            'interaction':True,'nativeInstalled':True,'character':media(folder/'character.webp'),'effect':media(folder/'night.webp')})
    payload = json.dumps(data, ensure_ascii=False, separators=(',', ':')).replace('</', '<\\/')
    html = TEMPLATE.replace('__MEDIA_DATA__', payload).replace('__ARCHIVE_COUNT__',str(sum(i['status']=='archive' for i in data)))
    (ROOT / 'index.html').write_text(html)
    print(json.dumps({'latest_motions': sum(i['status']!='archive' for i in data), 'previous_versions': sum(i['status']=='archive' for i in data),
                      'verified_media_sources': len(data)*2,
                      'html_bytes': len(html.encode()),
                      'source_gifs_unchanged': True}, ensure_ascii=False))


TEMPLATE = r'''<!doctype html>
<html lang="ko">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="color-scheme" content="light">
<title>천사 레토 · 모션 모아보기</title>
<style>
:root{--ink:#302e39;--muted:#77727c;--gold:#a87b32;--line:#e7e0d7;--paper:#fffdf9;--soft:#f5f0e8}
*{box-sizing:border-box}body{margin:0;background:#f7f4ee;color:var(--ink);font:15px/1.65 -apple-system,BlinkMacSystemFont,"Apple SD Gothic Neo","Noto Sans KR",sans-serif}
button,a{-webkit-tap-highlight-color:transparent}button{font:inherit;cursor:pointer}a{color:inherit}button:focus-visible,a:focus-visible,summary:focus-visible{outline:3px solid #ac934e;outline-offset:4px}[hidden]{display:none!important}
header{max-width:1260px;margin:auto;padding:66px 28px 30px}.eyebrow{color:var(--gold);font-size:12px;font-weight:700;letter-spacing:.13em}.headline{display:flex;align-items:end;justify-content:space-between;gap:20px;margin:12px 0}h1{font-size:clamp(30px,4.5vw,48px);line-height:1.2;letter-spacing:-.055em;margin:0;font-weight:750}header p{color:var(--muted);margin:18px 0 0}.count{font-size:13px;color:var(--muted);white-space:nowrap;padding-bottom:3px}
.controls-wrap{position:sticky;top:0;z-index:5;background:#f7f4eef2;backdrop-filter:blur(16px);border-block:1px solid var(--line)}.controls{max-width:1260px;margin:auto;padding:15px 28px;display:flex;flex-wrap:wrap;align-items:center;gap:12px}.tabs{display:flex;border:1px solid var(--line);background:#eee9e0;border-radius:12px;padding:4px;gap:3px}.tabs button{border:0;background:transparent;border-radius:8px;padding:7px 15px;color:var(--muted);font-size:13px}.tabs button[aria-pressed=true]{background:var(--paper);color:var(--ink);box-shadow:0 1px 4px #49381412}.playback{margin-left:auto;display:flex;gap:6px}.playback button{border:1px solid var(--line);border-radius:10px;background:var(--paper);font-size:13px;padding:8px 13px}.playback button[aria-pressed=true]{border-color:#b4945d;color:#886328}.filters{max-width:1260px;margin:auto;padding:22px 28px 6px;display:flex;flex-wrap:wrap;gap:7px}.filters button{font-size:13px;color:var(--muted);background:transparent;border:1px solid transparent;border-radius:30px;padding:7px 13px}.filters button[aria-pressed=true]{color:var(--ink);background:var(--paper);border-color:var(--line)}
main{max-width:1260px;margin:auto;padding:20px 28px 60px}.grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:22px}.card{border:1px solid var(--line);background:var(--paper);border-radius:20px;overflow:hidden;box-shadow:0 5px 18px #41331f04;display:flex;flex-direction:column}.card-head{padding:19px 20px 0;display:flex;align-items:center;justify-content:space-between;gap:10px}.card h2{font-size:17px;letter-spacing:-.035em;margin:0}.badge{font-size:10px;font-weight:650;letter-spacing:.015em;padding:4px 8px;border-radius:6px;white-space:nowrap;background:#eeedf2;color:#746e83}.badge.selected{background:#f0eadb;color:#8b6c35}.badge.draft{background:#f9e8d8;color:#a16630}.badge.archive{background:#ecebe8;color:#79756f}.image-button{display:block;position:relative;width:100%;border:0;padding:0;background:transparent;aspect-ratio:576/544;margin-top:8px;overflow:hidden}.image-button img{width:100%;height:100%;object-fit:contain;display:block}.zoom-hint{position:absolute;right:16px;bottom:10px;background:#fffdf9e8;border:1px solid var(--line);border-radius:20px;font-size:11px;padding:3px 9px;color:var(--muted);opacity:0;transition:opacity .15s}.image-button:hover .zoom-hint,.image-button:focus-visible .zoom-hint{opacity:1}.card-body{padding:8px 20px 20px;flex:1;display:flex;flex-direction:column}.meta{font-size:11px;color:#9b8b75;letter-spacing:.025em;margin-bottom:8px}.description{font-size:13px;color:var(--muted);margin:0 0 12px;min-height:43px}.open-link{font-size:12px;text-underline-offset:4px;color:#8c713e;align-self:flex-start;margin-top:auto}.next-note{font-size:12px;line-height:1.65;color:#8d6236;background:#faf0e4;border:1px solid #efdfc8;border-radius:10px;padding:11px 12px;margin:0 0 13px}.draft.card{border-color:#e7c9a6}
details{margin-top:38px;border-top:1px solid var(--line);padding-top:20px}summary{cursor:pointer;color:var(--muted);font-size:14px;padding:5px 0}.archive-grid{max-width:390px;margin-top:20px}.footer-note{font-size:12px;color:#8c8790;margin-top:34px;padding-top:20px;border-top:1px solid var(--line)}.footer-note span{display:block;margin-top:4px}dialog{border:1px solid var(--line);border-radius:22px;max-width:min(800px,94vw);width:800px;max-height:94dvh;padding:0;background:var(--paper);color:var(--ink);box-shadow:0 20px 90px #201c2745}dialog::backdrop{background:#2723319c;backdrop-filter:blur(5px)}.dialog-head{display:flex;align-items:center;justify-content:space-between;padding:19px 22px;border-bottom:1px solid var(--line)}.dialog-head h2{font-size:17px;margin:0}.close{border:1px solid var(--line);border-radius:8px;padding:5px 11px;background:transparent;font-size:12px}.dialog-image{display:block;max-width:100%;max-height:66dvh;margin:auto;object-fit:contain;width:auto}.dialog-footer{padding:12px 22px 20px;font-size:12px;color:var(--muted)}.dialog-footer p{margin:0 0 8px}.dialog-footer a{color:var(--gold);text-underline-offset:4px}.noscript{padding:24px;background:#fff1df;border:1px solid #e3d0ae;border-radius:12px}
@media(min-width:1500px){.grid{gap:26px}}@media(max-width:1000px){.grid{grid-template-columns:repeat(2,minmax(0,1fr))}.count{display:none}header{padding-top:42px}}@media(max-width:620px){header{padding:32px 18px 24px}.controls{padding:12px 18px;gap:10px}.playback{margin-left:0}.tabs button{padding:7px 10px}.filters{padding:15px 18px 0;gap:1px}.filters button{padding:6px 9px;font-size:12px}main{padding:18px 18px 40px}.grid{grid-template-columns:1fr;gap:19px}.card-head{padding-top:17px}.description{min-height:0}.archive-grid{max-width:none}}

body[data-preview="dark"]{--stage-base:#131d32;--pane:#263953;--pane2:#36334e;--stage-ink:#8699b32b;--window-line:#8091aa33}
body[data-preview="light"]{--stage-base:#edf0f5;--pane:#ffffff;--pane2:#e2e5ee;--stage-ink:#8e9caa36;--window-line:#8392a03d}
body[data-preview="checker"]{--stage-base:#f4f4f5;--pane:#fff;--pane2:#eee;--stage-ink:#ddd;--window-line:#ddd}
.image-button,.dialog-stage{isolation:isolate;background:var(--stage-base);position:relative}
.image-button img,.dialog-image{position:relative;z-index:1}.zoom-hint{z-index:2}.dialog-stage{display:grid;place-items:center;overflow:hidden}.dialog-image{max-width:100%;max-height:66dvh}
body[data-preview="checker"] .image-button,body[data-preview="checker"] .dialog-stage{background-color:#f4f4f5;background-image:conic-gradient(#dcdde0 25%,transparent 0 50%,#dcdde0 0 75%,transparent 0);background-size:24px 24px}
.backgrounds{display:flex;align-items:center;flex-wrap:wrap;gap:4px}.backgrounds span{font-size:11px;color:var(--muted);margin-right:3px}.backgrounds button{font-size:11px;border:1px solid var(--line);border-radius:8px;background:var(--paper);padding:7px 9px;color:var(--muted)}.backgrounds button[aria-pressed=true]{border-color:#a99bc4;color:#66577e;background:#f1edf7}
.archive-grid{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:22px;max-width:none}.controls{gap:10px}.playback{margin-left:auto}.playback button{font-size:11px}
@media(max-width:1000px){.archive-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.playback{margin-left:0}}
@media(max-width:620px){.archive-grid{grid-template-columns:1fr}.backgrounds{order:3;width:100%}.playback{margin-left:auto}.backgrounds button{padding:6px 9px}}

</style>
</head>
<body data-preview="dark">
<header><div class="eyebrow">천사 레토 · 타토 &amp; 멜로디 · 모션 이펙트 보강</div><div class="headline"><h1>모션 모아보기</h1><span class="count">7개 상태 + 왼쪽 시선 시안</span></div><p>마우스를 왼쪽으로 따라보며 타토·멜로디와 반응하는 시안을 추가했어요. 기존 7개 상태는 그대로예요. 배경을 바꿔 투명도를 비교하고, 이미지를 누르면 크게 볼 수 있어요.</p></header>
<div class="controls-wrap"><div class="controls"><div class="tabs" role="group" aria-label="효과 표시"><button type="button" data-mode="effect" aria-pressed="true">효과 포함</button><button type="button" data-mode="character" aria-pressed="false">캐릭터만</button></div><div class="backgrounds" role="group" aria-label="미리보기 배경"><span>배경</span><button type="button" data-bg="dark" aria-pressed="true">어두운 배경</button><button type="button" data-bg="light" aria-pressed="false">밝은 배경</button><button type="button" data-bg="checker" aria-pressed="false">체크</button></div><div class="playback" role="group" aria-label="움직임 표시"><button type="button" data-play="true" aria-pressed="true">움직임 켜기</button><button type="button" data-play="false" aria-pressed="false">정지 화면</button></div></div></div>
<nav class="filters" aria-label="동작 선택"><button type="button" data-filter="all" aria-pressed="true">전체</button><button type="button" data-filter="idle" aria-pressed="false">기본 대기</button><button type="button" data-filter="running" aria-pressed="false">작업 중</button><button type="button" data-filter="waiting" aria-pressed="false">입력 대기</button><button type="button" data-filter="failed" aria-pressed="false">실패 · 위로</button><button type="button" data-filter="waving" aria-pressed="false">작업 완료</button><button type="button" data-filter="jumping" aria-pressed="false">클릭 반응</button><button type="button" data-filter="sleeping" aria-pressed="false">수면</button><button type="button" data-filter="drag" aria-pressed="false">좌우 드래그</button><button type="button" data-filter="gaze" aria-pressed="false">시선 상호작용</button></nav>
<main><p><a href="../motion/interactions-v2-20261106/index.html">좌우 비행 · 마우스 따라보기 직접 확인하기 ↗</a></p><noscript><p class="noscript">이 모아보기는 JavaScript를 켜야 표시됩니다. 각 원본 GIF는 같은 폴더의 모션 파일에 보관되어 있습니다.</p></noscript><section class="grid" id="latest" aria-label="현재 동작 GIF"></section><details id="archive"><summary>이전 효과·시안 보기 · __ARCHIVE_COUNT__개</summary><div class="archive-grid" id="archive-grid"></div></details><p class="footer-note">기존 7개 상태와 별도로 좌우 드래그·16방향 시선·기본 대기 랜덤 변형을 추가했어요.<span>배경을 바꿔 가장자리 투명도를 비교해요. 원본 비율·위치와 앱 동작 확인은 별도로 남아 있습니다. 정지 화면은 첫 장면이에요.</span></p></main>
<dialog id="viewer" aria-labelledby="viewer-title"><div class="dialog-head"><h2 id="viewer-title"></h2><button type="button" class="close" id="close-viewer">닫기</button></div><div class="dialog-stage"><img class="dialog-image" id="viewer-image" alt=""></div><div class="dialog-footer"><p id="viewer-note"></p><a id="viewer-open" target="_blank" rel="noopener">이 GIF 열기 ↗</a></div></dialog>
<script id="media-data" type="application/json">__MEDIA_DATA__</script>
<script>
'use strict';
const items=JSON.parse(document.getElementById('media-data').textContent);
let mode='effect', playing=!window.matchMedia('(prefers-reduced-motion: reduce)').matches, filter='all', current=null;
const cards=new Map(), viewer=document.getElementById('viewer'), archive=document.getElementById('archive');
const make=(tag,className,text)=>{const e=document.createElement(tag);if(className)e.className=className;if(text!==undefined)e.textContent=text;return e;};
function renderCard(item){
 const card=make('article','card '+item.status);card.dataset.state=item.state;
 const head=make('div','card-head'),title=make('h2','',item.title),badge=make('span','badge '+item.status,item.label);head.append(title,badge);
 const button=make('button','image-button');button.type='button';button.setAttribute('aria-label',item.title+' 크게 보기');
 const image=make('img');image.alt=item.title+' 애니메이션';image.decoding='async';image.src=item[mode].poster;image.width=item.effect.size[0];image.height=item.effect.size[1];
 button.append(image,make('span','zoom-hint','크게 보기 ↗'));button.addEventListener('click',()=>openViewer(item));
 const body=make('div','card-body'),meta=make('div','meta',(item.effect.ms/1000).toFixed(1)+'초 반복 · '+item.character.frames+'컷');body.append(meta,make('p','description',item.description));
 if(item.next)body.append(make('p','next-note',item.next));
 const link=make('a','open-link',item[mode].transparent?'투명 애니메이션 열기 ↗':'이전 GIF 열기 ↗');link.href=item[mode].src;link.target='_blank';link.rel='noopener';body.append(link);card.append(head,button,body);
 cards.set(item.id,{item,card,image,link,inView:false});return card;
}
for(const item of items)document.getElementById(item.status==='archive'?'archive-grid':'latest').append(renderCard(item));
function updateCard(entry){
 const visible=!entry.card.hidden&&(entry.item.status!=='archive'||archive.open);
 const media=entry.item[mode],next=playing&&visible&&entry.inView?media.src:media.poster;
 if(entry.image.getAttribute('src')!==next)entry.image.src=next;
 entry.link.href=media.src;entry.link.textContent=media.transparent?'투명 애니메이션 열기 ↗':'이전 GIF 열기 ↗';
}
const observer=new IntersectionObserver(entries=>{for(const e of entries){const entry=cards.get(e.target.dataset.id);entry.inView=e.isIntersecting;updateCard(entry);}},{rootMargin:'140px 0px'});
for(const [id,entry] of cards){entry.card.dataset.id=id;observer.observe(entry.card);}
function refresh(){
 const pending=[...document.querySelectorAll('[data-pending-state]')];
 for(const card of pending)card.hidden=filter!=='all'&&card.dataset.pendingState!==filter;
 document.getElementById('pending').hidden=pending.every(c=>c.hidden);
 for(const entry of cards.values()){entry.card.hidden=filter!=='all'&&entry.item.state!==filter;updateCard(entry);}
 const previous=items.filter(i=>i.status==='archive'&&(filter==='all'||i.state===filter));archive.hidden=previous.length===0;archive.querySelector('summary').textContent='이전 효과·시안 보기 · '+previous.length+'개';
 document.querySelectorAll('[data-mode]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.mode===mode)));
 document.querySelectorAll('[data-play]').forEach(b=>b.setAttribute('aria-pressed',String((b.dataset.play==='true')===playing)));
 document.querySelectorAll('[data-filter]').forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.filter===filter)));
 if(viewer.open&&current)updateViewer();
}
function updateViewer(){
 const media=current[mode],image=document.getElementById('viewer-image');image.src=playing?media.src:media.poster;image.alt=current.title+' '+(mode==='effect'?'효과 포함':'캐릭터만');
 document.getElementById('viewer-title').textContent=current.title+' · '+current.label;
 document.getElementById('viewer-note').textContent=current.description+(current.next?' '+current.next:'');
 document.getElementById('viewer-open').href=media.src;document.getElementById('viewer-open').textContent=media.transparent?'투명 애니메이션 열기 ↗':'이전 GIF 열기 ↗';
}
function openViewer(item){current=item;updateViewer();viewer.showModal();}
document.getElementById('close-viewer').addEventListener('click',()=>viewer.close());
viewer.addEventListener('click',e=>{if(e.target===viewer){const r=viewer.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)viewer.close();}});
viewer.addEventListener('close',()=>{document.getElementById('viewer-image').removeAttribute('src');current=null;});
document.querySelectorAll('[data-mode]').forEach(b=>b.addEventListener('click',()=>{mode=b.dataset.mode;refresh();}));
document.querySelectorAll('[data-play]').forEach(b=>b.addEventListener('click',()=>{playing=b.dataset.play==='true';refresh();}));
document.querySelectorAll('[data-filter]').forEach(b=>b.addEventListener('click',()=>{filter=b.dataset.filter;refresh();}));
document.querySelectorAll('[data-bg]').forEach(b=>b.addEventListener('click',()=>{document.body.dataset.preview=b.dataset.bg;document.querySelectorAll('[data-bg]').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));}));
archive.addEventListener('toggle',()=>{for(const entry of cards.values())if(entry.item.status==='archive')updateCard(entry);});
refresh();
</script>
</body>
</html>
'''

if __name__ == '__main__':
    main()
