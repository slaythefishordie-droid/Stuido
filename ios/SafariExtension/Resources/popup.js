const writeButton = document.querySelector('#write');
const readButton = document.querySelector('#read');
const status = document.querySelector('#status');

async function request(action) {
  writeButton.disabled = readButton.disabled = true;
  status.textContent = '正在访问共享目录…';
  try {
    const result = await browser.runtime.sendNativeMessage('org.knowledge-studio.prototype', { action });
    if (!result?.ok) throw new Error(result?.error ?? '原生扩展未返回有效结果。');
    document.querySelector('#app').textContent = result.app;
    document.querySelector('#safari').textContent = result.safari;
    status.textContent = '读取完成，请与主 App 核对相同编号。';
  } catch (error) {
    document.querySelector('#app').textContent = '读取未完成';
    document.querySelector('#safari').textContent = '读取未完成';
    status.textContent = error.message ?? String(error);
  } finally {
    writeButton.disabled = readButton.disabled = false;
  }
}
writeButton.addEventListener('click', () => request('writeProbe'));
readButton.addEventListener('click', () => request('readProbe'));
request('readProbe');
