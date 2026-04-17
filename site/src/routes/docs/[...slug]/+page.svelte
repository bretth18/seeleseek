<script lang="ts">
import DocLayout from '$lib/components/DocLayout.svelte';

let { data } = $props();
</script>

<DocLayout title={data.meta.title} description={data.meta.description}>
	{@html data.html}
</DocLayout>

{#if data.prev || data.next}
	<nav class="mt-12 flex flex-col gap-4 sm:flex-row sm:items-center sm:justify-between border-t border-border pt-6 text-xs font-mono">
		{#if data.prev}
			<a href="/docs/{data.prev.slug}" class="group flex flex-col items-start no-underline min-w-0">
				<span class="text-muted-foreground tracking-tighter">← prev</span>
				<span class="text-foreground group-hover:text-accent transition-colors truncate max-w-full">
					{data.prev.title}
				</span>
			</a>
		{:else}
			<div class="hidden sm:block"></div>
		{/if}
		{#if data.next}
			<a href="/docs/{data.next.slug}" class="group flex flex-col sm:items-end no-underline min-w-0">
				<span class="text-muted-foreground tracking-tighter">next →</span>
				<span class="text-foreground group-hover:text-accent transition-colors truncate max-w-full">
					{data.next.title}
				</span>
			</a>
		{/if}
	</nav>
{/if}
