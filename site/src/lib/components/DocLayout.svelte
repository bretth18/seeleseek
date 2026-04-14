<script lang="ts" module>
	export interface DocMetadata {
		title: string;
		description: string;
		order: number;
		category?: string;
		layout: string;
	}
</script>

<script lang="ts">
	import type { Snippet } from 'svelte';

	let {
		title,
		description,
		children
	}: {
		title: string;
		description: string;
		children: Snippet;
	} = $props();
</script>

<svelte:head>
	<title>{title} — seeleseek docs</title>
	<meta name="description" content={description} />
</svelte:head>

<article class="prose prose-invert max-w-none" data-pagefind-body>
	<p class="text-xs font-mono text-muted-foreground tracking-tighter not-prose mb-2">
		// {description}
	</p>
	<h1 class="tracking-tighter">{title}</h1>
	{@render children()}
</article>
