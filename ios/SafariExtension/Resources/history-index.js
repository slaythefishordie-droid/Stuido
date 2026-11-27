(() => {
  // Rebuilt only after a confirmed native refresh. Holds references, not copied marks.
  function build(marks) {
    const groups = new Map(), orderedMarks = new Map();
    for (const mark of marks) {
      if (mark.deletedAt != null) continue;
      let group = groups.get(mark.videoID);
      if (!group) {
        group = { id: mark.videoID, title: mark.title, recent: mark.createdAt, marks: [], titles: new Set() };
        groups.set(mark.videoID, group);
      }
      group.marks.push(mark);
      group.titles.add(mark.title.toLowerCase());
      if (mark.createdAt > group.recent) { group.recent = mark.createdAt; group.title = mark.title; }
    }
    for (const group of groups.values()) group.titles = [...group.titles];
    const recent = [...groups.values()].sort((a, b) => b.recent - a.recent);
    let watchedReference, byWatch;
    return {
      group: id => groups.get(id),
      videos(query, currentID, sort, watched) {
        let ordered = recent;
        if (sort === 'watched') {
          if (watchedReference !== watched) {
            // Start with insertion order to preserve the original stable tie order.
            byWatch = [...groups.values()].sort((a, b) =>
              ((watched[b.id] ?? 0) - (watched[a.id] ?? 0)) || b.recent - a.recent);
            watchedReference = watched;
          }
          ordered = byWatch;
        }
        return ordered.filter(group => (currentID === undefined || group.id === currentID) &&
          (group.id.includes(query) || group.titles.some(title => title.includes(query))));
      },
      marks(id) {
        if (!orderedMarks.has(id)) orderedMarks.set(id, [...(groups.get(id)?.marks ?? [])].sort((a, b) => a.seconds - b.seconds));
        return orderedMarks.get(id);
      }
    };
  }
  globalThis.KnowledgeHistoryIndex = { build };
})();
