const LANG_COLORS = {
  Go:         '#00ADD8',
  HTML:       '#e34c26',
  JavaScript: '#f1e05a',
  TypeScript: '#3178c6',
  Python:     '#3572a5',
  Rust:       '#dea584',
  CSS:        '#563d7c',
  Shell:      '#89e051',
};

const FALLBACK_REPOS = [
  {
    name: 'budge',
    description: '🐦 A budget and asset manager for self-hosting Kiwis',
    html_url: 'https://github.com/TheQueenIsDead/budge',
    stargazers_count: 3,
    language: 'Go',
    homepage: '',
  },
  {
    name: 'DNSCDN',
    description: '📁 A CLI tool written in Go for storing and retrieving files on the Domain Name System',
    html_url: 'https://github.com/TheQueenIsDead/DNSCDN',
    stargazers_count: 2,
    language: 'Go',
    homepage: '',
  },
  {
    name: 'QCKSCRL',
    description: 'A lightweight keyboard-driven quick-scroll utility built for the browser.',
    html_url: 'https://github.com/TheQueenIsDead/QCKSCRL',
    stargazers_count: 0,
    language: 'HTML',
    homepage: null,
  },
  {
    name: 'QCKCUT',
    description: '🎥 A browser movie editor for clipping and sequencing video highlights',
    html_url: 'https://github.com/TheQueenIsDead/QCKCUT',
    stargazers_count: 0,
    language: 'Javascript',
    homepage: null,
  },
  {
    name: 'GoPhormula',
    description: '🏎️ Golang utilities for everything Formula 1',
    html_url: 'https://github.com/TheQueenIsDead/GoPhormula',
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
      const goCount = this.repos.filter(r => r.language === 'Go').length;
      const langs = [...new Set(this.repos.map(r => r.language).filter(Boolean))];
      return goCount > this.repos.length / 2 ? 'Go' : langs[0] || '—';
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