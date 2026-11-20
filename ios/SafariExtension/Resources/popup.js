const writeButton = document.querySelector('#write');
const readButton = document.querySelector('#read');
const appRecord = document.querySelector('#app');
const safariRecord = document.querySelector('#safari');
const status = document.querySelector('#status');
const requestTimeoutMilliseconds = 10_000;
let requestPending = false;

async function request(action) {
  if (requestPending) return;
  requestPending = true;
  writeButton.disabled = true;
  readButton.disabled = true;
  status.textContent = '正在访问共享目录…';
  let timeout;

  try {
    const deadline = new Promise((_, reject) => {
      timeout = setTimeout(() => {
        reject(new Error('共享请求超时，保存结果待确认。请先读取记录后再决定是否重试写入。'));
      }, requestTimeoutMilliseconds);
    });
    const result = await Promise.race([
      browser.runtime.sendNativeMessage('org.knowledge-studio.prototype', { action }),
      deadline
    ]);
    if (result?.ok !== true) {
      throw new Error(typeof result?.error === 'string' ? result.error : '原生扩展未返回有效结果。');
    }
    if (typeof result.app !== 'string' || typeof result.safari !== 'string') {
      throw new Error('共享记录响应格式无效，请重新读取。');
    }
    appRecord.textContent = result.app;
    safariRecord.textContent = result.safari;
    status.textContent = '读取完成，请与主 App 核对相同编号。';
  } catch (error) {
    appRecord.textContent = '读取未完成';
    safariRecord.textContent = '读取未完成';
    status.textContent = typeof error?.message === 'string' ? error.message : '共享请求失败，请重新读取。';
  } finally {
    clearTimeout(timeout);
    requestPending = false;
    writeButton.disabled = false;
    readButton.disabled = false;
  }
}

writeButton.addEventListener('click', () => request('writeProbe'));
readButton.addEventListener('click', () => request('readProbe'));
request('readProbe');
