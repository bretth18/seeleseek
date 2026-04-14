<script lang="ts">
	import { page } from '$app/state';
	import type { DocSection } from '$lib/utils/docs';

	let { sections }: { sections: DocSection[] } = $props();

	function isActive(slug: string): boolean {
		return page.url.pathname === `/docs/${slug}`;
	}
</script>

<nav class="w-56 shrink-0" aria-label="Documentation">
	<div class="sticky top-16 max-h-[calc(100vh-5rem)] space-y-6 overflow-y-auto py-2">
		{#each sections as section}
			<div>
				<h3 class="mb-2 text-[10px] font-mono tracking-tighter text-muted-foreground uppercase">
					// {section.name}
				</h3>
				<ul class="space-y-0 border-l border-border">
					{#each section.pages as doc}
						<li>
							<a
								href="/docs/{doc.slug}"
								class="block -ml-px border-l pl-3 pr-2 py-1 text-xs font-mono transition-colors {isActive(doc.slug)
									? 'border-accent text-foreground'
									: 'border-transparent text-muted-foreground hover:text-foreground hover:border-border'}"
							>
								{doc.title}
							</a>
						</li>
					{/each}
				</ul>
			</div>
		{/each}
	</div>
</nav>
