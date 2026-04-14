<script lang="ts">
	import type { Snippet } from 'svelte';
	import { typography } from './tokens';

	type Size = 'display' | 'h1' | 'h2' | 'h3';
	type Tag = 'h1' | 'h2' | 'h3' | 'h4';

	interface Props {
		as?: Tag;
		size?: Size;
		class?: string;
		children: Snippet;
	}

	let { as = 'h2', size = 'h2', class: className = '', children }: Props = $props();
</script>

<svelte:element this={as} class="{typography[size]} {className}">
	{@render children()}
</svelte:element>
