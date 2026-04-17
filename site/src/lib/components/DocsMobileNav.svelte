<script lang="ts">
import { page } from '$app/state';
import type { DocSection } from '$lib/utils/docs';

let { sections }: { sections: DocSection[] } = $props();

const current = $derived.by(() => {
	for (const section of sections) {
		for (const doc of section.pages) {
			if (page.url.pathname === `/docs/${doc.slug}`) {
				return { section: section.name, doc: doc.title };
			}
		}
	}
	return null;
});

const label = $derived(current ? `${current.section} › ${current.doc}` : 'Documentation');
</script>

<details class="group border-b border-border lg:hidden">
	<summary
		class="cursor-pointer list-none flex items-baseline justify-between gap-4 px-5 md:px-10 py-4 text-xs font-mono tracking-tighter text-muted-foreground"
	>
		<span class="truncate">// {label}</span>
		<span class="text-foreground/40 group-open:text-accent transition-colors" aria-hidden="true">
			▾
		</span>
	</summary>
	<nav
		class="border-t border-border px-5 md:px-10 py-4 space-y-5"
		aria-label="Documentation"
	>
		{#each sections as section}
			<div>
				<h3
					class="mb-2 text-[10px] font-mono tracking-tighter text-muted-foreground uppercase"
				>
					// {section.name}
				</h3>
				<ul class="space-y-0 border-l border-border">
					{#each section.pages as doc}
						{@const active = page.url.pathname === `/docs/${doc.slug}`}
						<li>
							<a
								href="/docs/{doc.slug}"
								class="block -ml-px border-l pl-3 pr-2 py-1.5 text-xs font-mono transition-colors {active
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
	</nav>
</details>
