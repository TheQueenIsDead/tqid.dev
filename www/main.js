const LANG_COLORS = {
  Go:         '#00ADD8',
  HTML:       '#e34c26',
  JavaScript: '#f1e05a',
  TypeScript: '#3178c6',
  Python:     '#3572a5',
  Rust:       '#dea584',
  CSS:        '#563d7c',
  Shell:      '#89e051',
  Dart:       '#00b4ab',
};

const FALLBACK_REPOS = [
  {
    name: 'calora',
    description: '🍏 Flutter nutrition tracker with NZ/AU food database, recipes, and barcode lookup.',
    html_url: 'https://github.com/TheQueenIsDead/calora',
    stargazers_count: 1,
    language: 'Dart',
    homepage: '',
  },
  {
    name: 'budge',
    description: '🐦 A budget and asset manager for self-hosting Kiwis',
    html_url: 'https://github.com/TheQueenIsDead/budge',
    stargazers_count: 3,
    language: 'Go',
    homepage: '',
  },
  {
    name: 'dnscdn',
    description: '📁 A CLI tool written in Go for storing and retrieving files on the Domain Name System',
    html_url: 'https://github.com/TheQueenIsDead/dnscdn',
    stargazers_count: 2,
    language: 'Go',
    homepage: '',
  },
  {
    name: 'QCKSCRL',
    description: '📷 A browser based carousel composer for social media',
    html_url: 'https://github.com/TheQueenIsDead/QCKSCRL',
    stargazers_count: 0,
    language: 'JavaScript',
    homepage: 'https://scrl.tqid.dev/',
  },
  {
    name: 'QCKCUT',
    description: '🎥 A browser movie editor for clipping and sequencing video highlights',
    html_url: 'https://github.com/TheQueenIsDead/QCKCUT',
    stargazers_count: 0,
    language: 'JavaScript',
    homepage: 'https://cut.tqid.dev/',
  },
  {
    name: 'gophormula',
    description: '🏎️ Golang utilities for everything Formula 1',
    html_url: 'https://github.com/TheQueenIsDead/gophormula',
    stargazers_count: 0,
    language: 'Go',
    homepage: '',
  },
  {
    name: 'go-chat',
    description: '💬 A chatroom implemented in Go with NATS and Datastar',
    html_url: 'https://github.com/TheQueenIsDead/go-chat',
    stargazers_count: 0,
    language: 'Go',
    homepage: 'https://chat.tqid.dev/',
  },
  {
    name: 'gupdit',
    description: '⬆️ Check for software updates via Git at runtime',
    html_url: 'https://github.com/TheQueenIsDead/gupdit',
    stargazers_count: 1,
    language: null,
    homepage: '',
  },
];

const REPO_NAMES = ['Calora', 'Budge', 'DNSCDN', 'QCKSCRL', 'QCKCUT', 'GoPhormula', 'go-chat', 'gupdit'];

document.addEventListener('alpine:init', () => {
  Alpine.data('app', () => ({
    repos: FALLBACK_REPOS,

    get totalStars() {
      return this.repos.reduce((sum, r) => sum + (r.stargazers_count || 0), 0);
    },

    get primaryLang() {
      const counts = {};
      for (const r of this.repos) {
        if (r.language) counts[r.language] = (counts[r.language] || 0) + 1;
      }
      const ranked = Object.entries(counts).sort((a, b) => b[1] - a[1]);
      return ranked.length ? ranked[0][0] : '—';
    },

    langColor(lang) {
      return LANG_COLORS[lang] || '#71717a';
    },

    onMouseMove(event, el) {
      const r = el.getBoundingClientRect();
      el.style.setProperty('--mx', ((event.clientX - r.left) / r.width * 100) + '%');
      el.style.setProperty('--my', ((event.clientY - r.top) / r.height * 100) + '%');
    },

    async init() {
      try {
        const results = await Promise.all(
          REPO_NAMES.map(name =>
            fetch(`https://api.github.com/repos/TheQueenIsDead/${name}`, {
              headers: { Accept: 'application/vnd.github.v3+json' },
            })
              .then(r => r.ok ? r.json() : null)
              .catch(() => null)
          )
        );
        const live = results.filter(Boolean);
        if (live.length > 0) this.repos = live;
      } catch {}
    },
  }));
});