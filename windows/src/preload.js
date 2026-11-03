// 화면 쪽에 열어 주는 것은 이것뿐이다. 화면은 파일·셸에 직접 닿지 않는다.
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('retto', {
  onView: (callback) => ipcRenderer.on('view', (_event, value) => callback(value)),
  open: () => ipcRenderer.send('pet:open'),
  menu: () => ipcRenderer.send('pet:menu'),
  drag: (dx, dy) => ipcRenderer.send('pet:drag', { dx, dy }),
  report: () => ipcRenderer.invoke('setup:report'),
  install: () => ipcRenderer.invoke('setup:install'),
  uninstall: () => ipcRenderer.invoke('setup:uninstall'),
  openUrl: (url) => ipcRenderer.send('setup:open-url', url)
});
