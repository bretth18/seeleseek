<script lang="ts">
import DitheredImage from '$lib/components/DitheredImage.svelte';
import { dither, type RGBA } from './tokens';

type Tone = 'accent' | 'fg';

interface Props {
	src: string;
	alt?: string;
	tone?: Tone;
	cutoff?: number;
	class?: string;
}

let { src, alt = '', tone = 'accent', cutoff = 0.5, class: className = '' }: Props = $props();

const light: RGBA = $derived(tone === 'accent' ? dither.accent : dither.fg);
</script>

<DitheredImage
	{src}
	{alt}
	{cutoff}
	darkrgba={dither.bg}
	lightrgba={light}
	class="dither-canvas w-full {className}"
/>
