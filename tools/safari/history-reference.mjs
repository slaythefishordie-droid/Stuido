// Prior render projection, retained as a compatibility/performance control.
export function reference(marks, query, currentID, sort, watched) {
  const groups = new Map();
  for (const mark of marks) {
    if (mark.deletedAt != null || (currentID !== undefined && mark.videoID !== currentID)) continue;
    const group = groups.get(mark.videoID);
    if (group) {
      group.marks.push(mark);
      if (mark.createdAt > group.recent) { group.recent = mark.createdAt; group.title = mark.title; }
    } else groups.set(mark.videoID, { id: mark.videoID, title: mark.title, recent: mark.createdAt, marks: [mark] });
  }
  return [...groups.values()].filter(group => group.id.includes(query) || group.marks.some(mark => mark.title.toLowerCase().includes(query)))
    .sort((a, b) => (sort === 'watched' ? ((watched[b.id] ?? 0) - (watched[a.id] ?? 0)) : 0) || b.recent - a.recent);
}
export function fixture(count) {
  return Array.from({length: count}, (_, i) => ({id: i, videoID: String(i % 300).padStart(11, '0'),
    title: `Book ${i % 300} ${i % 7 ? '新版' : 'Old Title'}`, createdAt: Math.floor(i / 4), seconds: i % 61,
    deletedAt: i % 97 === 0 ? 1 : null}));
}
