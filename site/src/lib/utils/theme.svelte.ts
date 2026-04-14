import { browser } from '$app/environment';

function getInitialMode(): 'light' | 'dark' {
	if (!browser) return 'dark';
	const stored = localStorage.getItem('theme');
	if (stored === 'light' || stored === 'dark') return stored;
	if (window.matchMedia('(prefers-color-scheme: light)').matches) return 'light';
	return 'dark';
}

function createThemeStore() {
	let mode = $state<'light' | 'dark'>(getInitialMode());

	function apply() {
		if (!browser) return;
		document.documentElement.classList.toggle('dark', mode === 'dark');
		localStorage.setItem('theme', mode);
	}

	// Apply on init
	apply();

	return {
		get mode() {
			return mode;
		},
		toggle() {
			mode = mode === 'dark' ? 'light' : 'dark';
			apply();
		}
	};
}

export const theme = createThemeStore();
