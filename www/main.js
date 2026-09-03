const GITHUB_USER = 'TheQueenIsDead';

// Invoked from x-data in index.html, which lists the projects to feature;
// x-init then calls load() to refresh them from the GitHub API.
function app(pinned) {
  return {
    repos: pinned.map(r => ({ html_url: `https://github.com/${GITHUB_USER}/${r.name}`, ...r })),

    get totalStars() {
      return this.repos.reduce((sum, r) => sum + (r.stargazers_count || 0), 0);
    },

    get liveSites() {
      return this.repos.filter(r => r.homepage).length;
    },

    // Most-used language across the displayed projects. Each project is
    // weighted equally, so one big repo cannot outvote all the others.
    get primaryLang() {
      const totals = {};
      for (const repo of this.repos) {
        for (const lang of this.breakdown(repo)) {
          totals[lang.name] = (totals[lang.name] || 0) + Number(lang.percent);
        }
      }
      const ranked = Object.entries(totals).sort((a, b) => b[1] - a[1]);
      return ranked.length ? ranked[0][0] : '—';
    },

    // Bytes per language for one repo, or a single unit for its primary
    // language until load() has fetched the real numbers.
    bytes(repo) {
      return repo.languages || (repo.language ? { [repo.language]: 1 } : {});
    },

    // GitHub-style language split for one repo.
    breakdown(repo) {
      const bytes = this.bytes(repo);
      const total = Object.values(bytes).reduce((sum, n) => sum + n, 0);
      if (!total) return [];

      return Object.entries(bytes)
        .sort((a, b) => b[1] - a[1])
        .map(([name, n]) => ({ name, percent: (n / total * 100).toFixed(1) }));
    },

    onMouseMove(event, el) {
      const r = el.getBoundingClientRect();
      el.style.setProperty('--mx', ((event.clientX - r.left) / r.width * 100) + '%');
      el.style.setProperty('--my', ((event.clientY - r.top) / r.height * 100) + '%');
    },

    async load() {
      const res = await fetch(
        `https://api.github.com/users/${GITHUB_USER}/repos?per_page=100&sort=pushed`,
        { headers: { Accept: 'application/vnd.github.v3+json' } },
      ).catch(() => null);
      if (!res || !res.ok) return;

      // Only the repos listed in the markup are shown; the API just refreshes
      // them. Merging rather than replacing keeps the seeded language bytes.
      const live = await res.json();
      this.repos = this.repos.map(r => ({ ...r, ...live.find(l => l.name === r.name) }));

      // Per-repo language bytes. Skipped silently when rate limited, leaving
      // breakdown() on its single-language fallback.
      await Promise.all(this.repos.map(async (repo) => {
        if (!repo.languages_url) return;
        const res = await fetch(repo.languages_url).catch(() => null);
        if (res && res.ok) repo.languages = await res.json().catch(() => null);
      }));
    },
  };
}
