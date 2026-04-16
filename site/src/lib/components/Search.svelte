<script lang="ts">
import { onMount } from 'svelte';

let dialog: HTMLDialogElement;
let searchInput: HTMLInputElement;
let resultsContainer: HTMLDivElement;
let pagefind: any = null;

onMount(() => {
	function handleKeydown(e: KeyboardEvent) {
		if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
			e.preventDefault();
			dialog.showModal();
			searchInput?.focus();
		}
	}

	document.addEventListener('keydown', handleKeydown);
	return () => document.removeEventListener('keydown', handleKeydown);
});

async function loadPagefind() {
	if (pagefind) return pagefind;
	try {
		const url = '/pagefind/pagefind.js';
		pagefind = await import(/* @vite-ignore */ url);
		return pagefind;
	} catch {
		return null;
	}
}

async function handleSearch() {
	if (!searchInput?.value) {
		if (resultsContainer) resultsContainer.innerHTML = '';
		return;
	}

	const pf = await loadPagefind();
	if (!pf) {
		if (resultsContainer) {
			resultsContainer.innerHTML =
				'<p class="px-4 py-8 text-center text-xs font-mono text-muted-foreground">search index not available. run a build first.</p>';
		}
		return;
	}

	const search = await pf.search(searchInput.value);
	const results = await Promise.all(
		search.results.slice(0, 8).map((r: { data: () => Promise<unknown> }) => r.data())
	);

	if (resultsContainer) {
		if (results.length === 0) {
			resultsContainer.innerHTML =
				'<p class="px-4 py-8 text-center text-xs font-mono text-muted-foreground">no results.</p>';
		} else {
			resultsContainer.innerHTML = results
				.map((r: any) => {
					const url = String(r.url)
						.replace(/\.html$/, '')
						.replace(/\/index$/, '/');
					return `
					<a href="${url}" class="block px-4 py-3 hover:bg-muted transition-colors no-underline" onclick="this.closest('dialog').close()">
						<div class="text-sm font-medium text-foreground">${r.meta?.title || url}</div>
						<div class="mt-0.5 text-xs text-muted-foreground line-clamp-2 font-mono tracking-tighter">${r.excerpt}</div>
					</a>
				`;
				})
				.join('');
		}
	}
}
</script>

<button
	onclick={() => dialog.showModal()}
	class="flex items-center gap-2 border border-border px-2.5 py-1 text-xs font-mono text-muted-foreground transition-colors hover:text-foreground hover:border-muted-foreground bg-transparent cursor-pointer"
>
	<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="size-3.5">
		<path
			fill-rule="evenodd"
			d="M9 3.5a5.5 5.5 0 1 0 0 11 5.5 5.5 0 0 0 0-11ZM2 9a7 7 0 1 1 12.452 4.391l3.328 3.329a.75.75 0 1 1-1.06 1.06l-3.329-3.328A7 7 0 0 1 2 9Z"
			clip-rule="evenodd"
		/>
	</svg>
	<span class="hidden sm:inline">search</span>
	<kbd class="hidden sm:inline bg-muted px-1.5 py-0.5 text-[10px]">⌘K</kbd>
</button>

<!-- svelte-ignore a11y_no_noninteractive_element_interactions -->
<dialog
	bind:this={dialog}
	class="w-full max-w-lg border border-border bg-background text-foreground p-0 backdrop:bg-black/70"
	onkeydown={(e) => e.key === 'Escape' && dialog.close()}
>
	<div class="border-b border-border p-4">
		<input
			bind:this={searchInput}
			oninput={handleSearch}
			type="search"
			placeholder="search documentation..."
			class="w-full bg-transparent text-sm text-foreground outline-none placeholder:text-muted-foreground font-mono"
		/>
	</div>
	<div
		bind:this={resultsContainer}
		class="max-h-80 divide-y divide-border overflow-y-auto"
	></div>
</dialog>
