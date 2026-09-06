// 자체 검사가 ok 에 넣은 항목을 JSON 에도 다 찍는지 대조한다.
//
// 안 찍히면 그 항목이 실패해도 `{"ok":false}` 한 줄만 남고 무엇이 깨졌는지 알 수 없다.
// 2026-09-06 에 실제로 두 번 헤맸다 — 12개가 빠져 있었다.
import { readFileSync } from 'node:fs';

const path = new URL('../macos/Sources/SelfTest.swift', import.meta.url);
const lines = readFileSync(path, 'utf8').split('\n');
const pick = (prefix) => lines.find((line) => line.trim().startsWith(prefix));

const okLine = pick('let ok =');
const printLine = pick('print("{');
if (!okLine || !printLine) {
  console.error('SelfTest.swift 에서 ok 식이나 print 줄을 찾지 못했습니다');
  process.exit(1);
}

const flags = [...okLine.matchAll(/\b(\w+OK)\b/g)].map((m) => m[1]);
const printed = new Set([...printLine.matchAll(/\\\((\w+)\)/g)].map((m) => m[1]));
const missing = [...new Set(flags.filter((flag) => !printed.has(flag)))];

// 키가 겹치면 JSON.parse 가 뒤엣것으로 덮어써서 앞 항목이 사라진다.
const keys = [...printLine.matchAll(/\\"([A-Za-z0-9]+)\\":/g)].map((m) => m[1]);
const duplicated = [...new Set(keys.filter((key, i) => keys.indexOf(key) !== i))];

if (missing.length || duplicated.length) {
  if (missing.length) {
    console.error(`ok 에는 있는데 JSON 에 안 찍히는 항목 ${missing.length}개:`);
    for (const flag of missing) console.error(`  ${flag}`);
    console.error('  → print 줄에 \\"이름\\":\\(항목) 을 추가하세요.');
  }
  if (duplicated.length) {
    console.error(`JSON 키가 겹칩니다: ${duplicated.join(', ')}`);
    console.error('  → 겹치는 쪽 이름을 바꾸세요 (예: sleepRow 와 sleepRowOK).');
  }
  process.exit(1);
}

console.log(`  자체 검사 항목 ${flags.length}개가 모두 JSON 에 찍힙니다`);
