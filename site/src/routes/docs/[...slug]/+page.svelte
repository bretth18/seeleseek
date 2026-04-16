<script lang="ts">
import DocLayout from '$lib/components/DocLayout.svelte';

let { data } = $props();
</script>

<DocLayout title={data.meta.title} description={data.meta.description}>
	{@html data.html}
</DocLayout>

{#if data.prev || data.next}
	<nav class="mt-12 flex items-center justify-between border-t border-border pt-6 text-xs font-mono">
		{#if data.prev}
			<a href="/docs/{data.prev.slug}" class="group flex flex-col items-start no-underline">
				<span class="text-muted-foreground tracking-tighter">← prev</span>
				<span class="text-foreground group-hover:text-accent transition-colors">
					{data.prev.title}
				</span>
			</a>
		{:else}
			<div></div>
		{/if}
		{#if data.next}
			<a href="/docs/{data.next.slug}" class="group flex flex-col items-end no-underline">
				<span class="text-muted-foreground tracking-tighter">next →</span>
				<span class="text-foreground group-hover:text-accent transition-colors">
					{data.next.title}
				</span>
			</a>
		{/if}
	</nav>
{/if}
