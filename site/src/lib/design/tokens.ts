// Design tokens — single source of truth for non-color values.
// Colors live in layout.css as CSS variables.

export type RGBA = [number, number, number, number];

export const dither = {
	bg: [0, 0, 0, 255] as RGBA,
	fg: [245, 245, 245, 255] as RGBA,
	accent: [255, 11, 85, 255] as RGBA
} as const;

export const container = 'mx-auto max-w-6xl px-5 md:px-10';

export const section = {
	tight: 'py-12',
	base: 'py-16',
	loose: 'py-24 sm:py-32'
} as const;

// Type scale — modeled on brett-website's conventions.
// clamp()-scaled displays, tight negative tracking, tiny metadata.
export const typography = {
	display: 'font-bold text-[clamp(3rem,8vw,7rem)] leading-[0.9] tracking-[-0.04em]',
	h1: 'font-bold text-[clamp(2rem,5vw,4.5rem)] leading-[0.95] tracking-[-0.03em]',
	h2: 'font-bold text-3xl sm:text-4xl leading-tight tracking-[-0.03em]',
	h3: 'font-bold text-xl md:text-2xl leading-tight tracking-[-0.02em]',
	body: 'text-base text-foreground/70',
	bodySm: 'text-sm text-foreground/70',
	// Tiny uppercase-ish metadata — brett-website's signature
	meta: 'text-[11px] text-foreground/40 tracking-wide',
	eyebrow: 'text-[11px] text-foreground/40 tracking-wide uppercase',
	mono: 'text-xs font-mono'
} as const;
