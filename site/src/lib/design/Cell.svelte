<script lang="ts">
import type { Snippet } from 'svelte';

interface Props {
	href?: string;
	external?: boolean;
	pad?: 'sm' | 'md' | 'lg';
	class?: string;
	children: Snippet;
}

let { href, external = false, pad = 'md', class: className = '', children }: Props = $props();

const padding = $derived(
	{
		sm: 'p-5 md:p-6',
		md: 'p-6 md:p-8',
		lg: 'p-6 md:p-10 lg:p-16'
	}[pad]
);

const base = $derived(`${padding} ${className}`);
const interactive = 'group hover:bg-foreground/[0.02] transition-colors';
</script>

{#if href}
	<a
		{href}
		target={external ? '_blank' : undefined}
		rel={external ? 'noopener noreferrer' : undefined}
		class="{base} {interactive} no-underline block"
	>
		{@render children()}
	</a>
{:else}
	<div class={base}>
		{@render children()}
	</div>
{/if}
