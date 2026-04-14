<script lang="ts">
	import './layout.css';
	import Search from '$lib/components/Search.svelte';
	import { page } from '$app/state';

	let { children } = $props();

	let pathname = $derived(page.url.pathname);
	const isDocs = $derived(pathname.startsWith('/docs'));
	let menuOpen = $state(false);

	$effect(() => {
		pathname;
		menuOpen = false;
	});

	const navLinks = [
		{ href: '/docs/guide/getting-started', label: 'Docs', match: '/docs' },
		{ href: 'https://github.com/bretth18/seeleseek', label: 'GitHub', external: true }
	];
</script>

<svelte:head>
	<link rel="icon" type="image/png" href="/app-icon.png" />
</svelte:head>

<div class="flex min-h-dvh w-full flex-col">
	<header class="border-b border-border bg-background">
		<div class="flex items-center justify-between px-5 md:px-10 py-4 md:py-5">
			<div class="flex items-center gap-5 md:gap-8">
				<a href="/" class="group flex items-center gap-2 leading-none">
					<img src="/mascot.svg" alt="" class="w-6 h-6" />
					<span class="font-bold text-accent leading-none tracking-[-0.04em] text-xl md:text-2xl group-hover:text-accent/80 transition-colors">
						seeleseek
					</span>
				</a>

				<nav class="hidden sm:flex items-center gap-4 md:gap-5">
					{#each navLinks as link}
						<a
							href={link.href}
							target={link.external ? '_blank' : undefined}
							rel={link.external ? 'noopener noreferrer' : undefined}
							class="text-sm tracking-tight transition-colors {(link.match && pathname.startsWith(link.match)) ? 'text-foreground' : 'text-foreground/30 hover:text-foreground/60'}"
						>
							{link.label}
						</a>
					{/each}
				</nav>
			</div>

			<div class="hidden sm:flex items-center gap-4">
				<Search />
				<a
					href="/#download"
					class="text-sm font-bold text-accent hover:text-accent/60 transition-colors tracking-tight"
				>
					Download ↓
				</a>
			</div>

			<button
				type="button"
				class="sm:hidden bg-transparent border-none cursor-pointer p-1 text-foreground"
				onclick={() => menuOpen = !menuOpen}
				aria-label="Menu"
			>
				{#if menuOpen}
					<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M5 5l10 10M15 5L5 15"/></svg>
				{:else}
					<svg width="20" height="20" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M3 6h14M3 10h14M3 14h14"/></svg>
				{/if}
			</button>
		</div>

		{#if menuOpen}
			<div class="sm:hidden border-t border-border">
				<div class="px-5 py-3 flex flex-col gap-2 text-sm">
					<a href="/docs/guide/getting-started" class="text-foreground/60 hover:text-foreground">Docs</a>
					<a href="https://github.com/bretth18/seeleseek" class="text-foreground/60 hover:text-foreground">GitHub</a>
					<a href="/#download" class="text-accent">Download ↓</a>
				</div>
			</div>
		{/if}
	</header>

	<main class="flex-1 flex flex-col">
		{@render children()}
	</main>
</div>
