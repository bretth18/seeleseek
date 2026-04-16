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
	import { Seo } from '$lib/seo';

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

<Seo title={`${title} · docs`} {description} type="article" />

<article class="prose prose-invert max-w-none" data-pagefind-body>
	<p class="text-xs font-mono text-muted-foreground tracking-tighter not-prose mb-2">
		// {description}
	</p>
	<h1 class="tracking-tighter">{title}</h1>
	{@render children()}
</article>
