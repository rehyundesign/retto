// Geometry.swift의 크리스마스 시선 이동과 같은 인접 방향 재생 규칙.
export const gazeStepSeconds = 0.06;
export function nextGazeDirection(current, target) {
  const clockwise = (target - current + 16) % 16;
  if (clockwise === 0) return current;
  return (current + (clockwise <= 8 ? 1 : -1) + 16) % 16;
}

export function updateGazeMotion(item, target, time) {
  if (target === null) {
    item.displayLook = null;
    item.nextLookTime = time;
    return null;
  }
  if (item.displayLook == null) {
    item.displayLook = target;
    item.nextLookTime = time + gazeStepSeconds;
  } else if (item.displayLook === target) {
    // 목표에서 쉬던 시간을 이후 회전의 누적 이동으로 쓰지 않는다.
    item.nextLookTime = time + gazeStepSeconds;
  } else if (time >= item.nextLookTime) {
    // 느린 화면 갱신에서도 중간 자세를 건너뛰지 않는다.
    item.displayLook = nextGazeDirection(item.displayLook, target);
    item.nextLookTime = time + gazeStepSeconds;
  }
  return item.displayLook;
}
