(() => {
  function parse(text) {
    if (new TextEncoder().encode(text).length > 10 * 1024 * 1024) throw new Error('旧书签文件超过 10 MiB');
    const root = JSON.parse(text);
    if ((root.format ?? root.type) !== 'youtube-time-marks' || root.version !== 1) throw new Error('需要 youtube-time-marks v1 备份');
    const rows = root.marks ?? root.bookmarks;
    if (!Array.isArray(rows) || rows.length > 20_000) throw new Error('书签列表无效或超过 20,000 条');
    return rows.map(row => {
      const videoID = row.videoId ?? row.videoID, seconds = row.time ?? row.seconds;
      const createdAt = typeof row.createdAt === 'string' ? Date.parse(row.createdAt) : row.createdAt;
      if (!/^[A-Za-z0-9_-]{11}$/.test(videoID ?? '') || !Number.isInteger(seconds) || seconds < 0 || seconds > 3_155_760_000 ||
          typeof row.title !== 'string' || !row.title.trim() || new TextEncoder().encode(row.title).length > 4096 ||
          !Number.isFinite(createdAt) || createdAt < 0 || (row.note != null && (typeof row.note !== 'string' || new TextEncoder().encode(row.note).length > 20_000))) throw new Error('旧书签含无效视频、时间、标题或备注，未导入');
      return { version: 1, videoID, title: row.title, seconds, capturedSeconds: seconds, preRoll: 0, createdAt, note: row.note ?? '' };
    });
  }
  function serialize(marks) {
    return JSON.stringify({ format: 'youtube-time-marks', version: 1, exportedAt: new Date().toISOString(), marks: marks.filter(mark => mark.deletedAt == null).map(mark => ({ videoId: mark.videoID, title: mark.title, time: mark.seconds, createdAt: mark.createdAt, note: mark.note ?? '' })) }, null, 2);
  }
  globalThis.KnowledgeLegacy = { parse, serialize };
})();
