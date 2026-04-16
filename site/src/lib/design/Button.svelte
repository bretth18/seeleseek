<script lang="ts">
import type { Snippet } from 'svelte';

type Variant = 'primary' | 'secondary' | 'ghost';
type Size = 'sm' | 'md';

interface Props {
	href?: string;
	variant?: Variant;
	size?: Size;
	block?: boolean;
	class?: string;
	type?: 'button' | 'submit';
	onclick?: (e: MouseEvent) => void;
	children: Snippet;
}

let {
	href,
	variant = 'primary',
	size = 'md',
	block = false,
	class: className = '',
	type = 'button',
	onclick,
	children
}: Props = $props();

const base =
	'inline-flex items-center justify-center gap-2 text-xs font-mono no-underline transition-colors cursor-pointer border';
const sizes: Record<Size, string> = {
	sm: 'px-3 py-1',
	md: 'px-4 py-2'
};
const variants: Record<Variant, string> = {
	primary: 'bg-accent text-accent-foreground border-transparent hover:opacity-90',
	secondary: 'border-border text-foreground hover:bg-muted',
	ghost: 'border-transparent text-muted-foreground hover:text-foreground'
};
const cls = $derived(
	`${base} ${sizes[size]} ${variants[variant]} ${block ? 'w-full' : ''} ${className}`
);
</script>

{#if href}
	<a {href} class={cls}>{@render children()}</a>
{:else}
	<button {type} class={cls} {onclick}>{@render children()}</button>
{/if}
