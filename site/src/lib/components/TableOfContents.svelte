<script lang="ts">
	import type { TocEntry } from '$lib/utils/toc';

	let { entries }: { entries: TocEntry[] } = $props();
</script>

{#if entries.length > 0}
	<aside class="hidden w-48 shrink-0 xl:block" aria-label="Table of contents">
		<div class="sticky top-16 py-2">
			<h4 class="mb-3 text-[10px] font-mono tracking-tighter text-muted-foreground uppercase">
				// on this page
			</h4>
			<ul class="space-y-0 border-l border-border">
				{#each entries as entry}
					<li>
						<a
							href="#{entry.id}"
							class="block -ml-px border-l py-1 text-xs font-mono text-muted-foreground transition-colors hover:text-foreground hover:border-border border-transparent {entry.level === 3 ? 'pl-6' : 'pl-3'}"
						>
							{entry.text}
						</a>
					</li>
				{/each}
			</ul>
		</div>
	</aside>
{/if}
