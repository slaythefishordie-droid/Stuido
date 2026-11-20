const settingIDs = ['youtubeEnabled', 'preRoll', 'fontSize', 'buttonSide', 'collapsed'];
const settingsStatus = document.querySelector('#settingsStatus');
const scriptID = origin => 'site-' + Array.from(new TextEncoder().encode(origin)).map(byte => byte.toString(16)).join('');
async function loadSettings() {
  const values = await browser.storage.local.get(settingIDs);
  for (const key of settingIDs) {
    if (values[key] === undefined) continue;
    const element = document.getElementById(key);
    if (element.type === 'checkbox') element.checked = values[key]; else element.value = String(values[key]);
  }
  const scripts = await browser.scripting.getRegisteredContentScripts();
  document.querySelector('#sites').replaceChildren();
  for (const script of scripts.filter(script => script.id.startsWith('site-'))) {
    const row = document.createElement('p'); row.textContent = script.matches.join(', ');
    const button = document.createElement('button'); button.textContent = '停用';
    button.onclick = async () => { try { await browser.scripting.unregisterContentScripts({ ids: [script.id] }); await browser.permissions.remove({ origins: script.matches }); await loadSettings(); settingsStatus.textContent = '已停用，刷新该网页后移除采集按钮'; } catch (error) { settingsStatus.textContent = error.message; } };
    row.append(button); document.querySelector('#sites').append(row);
  }
}
document.querySelector('#saveSettings').onclick = async () => {
  try {
    const values = Object.fromEntries(settingIDs.map(key => { const element = document.getElementById(key); return [key, element.type === 'checkbox' ? element.checked : ['preRoll', 'fontSize'].includes(key) ? Number(element.value) : element.value]; }));
    await browser.storage.local.set(values); settingsStatus.textContent = '偏好已保存，刷新网页后生效';
  } catch (error) { settingsStatus.textContent = error.message; }
};
document.querySelector('#enableSite').onclick = async () => {
  try {
    const [tab] = await browser.tabs.query({ active: true, currentWindow: true });
    const url = new URL(tab.url);
    if (url.protocol !== 'https:') throw new Error('仅支持 HTTPS 网站');
    const origin = url.origin + '/*';
    if (!(await browser.permissions.request({ origins: [origin] }))) throw new Error('尚未获得此网站权限');
    const id = scriptID(origin), scripts = await browser.scripting.getRegisteredContentScripts();
    if (!scripts.some(script => script.id === id)) await browser.scripting.registerContentScripts([{ id, matches: [origin], js: ['adapters.js', 'generic.js'], runAt: 'document_idle' }]);
    await browser.scripting.executeScript({ target: { tabId: tab.id }, files: ['adapters.js', 'generic.js'] });
    await loadSettings(); settingsStatus.textContent = '此网站已启用选文与音频采集';
  } catch (error) { settingsStatus.textContent = error.message; }
};
loadSettings().catch(error => { settingsStatus.textContent = error.message; });
