<script lang="ts">
	import { Cell, Shot, typography } from '$lib/design';
	import DitheredImage from '$lib/components/DitheredImage.svelte';
	import { dither } from '$lib/design/tokens';
</script>

<svelte:head>
	<title>seeleseek</title>
	<meta name="description" content="A native Soulseek client for macOS. Built in SwiftUI." />
</svelte:head>

<div class="flex-1 flex flex-col">

	<!-- Hero slab -->
	<div class="border-b border-border">
		<Cell pad="lg">
			<div class="flex flex-col gap-12 md:gap-16">
				<DitheredImage
					src="/mascot.svg"
					alt="seeleseek"
					class="dither-canvas w-28 h-28 md:w-32 md:h-32"
					cutoff={0.5}
					darkrgba={dither.bg}
					lightrgba={dither.accent}
				/>
				<h1 class="{typography.display} text-accent">seeleseek</h1>
				<p class="max-w-xl text-foreground/50 text-[clamp(1rem,1.8vw,1.25rem)] leading-[1.4] tracking-[-0.01em]">
					A Soulseek client for macOS. Built in SwiftUI.
				</p>
			</div>
		</Cell>
	</div>

	<!-- Two-cell action row -->
	<div class="grid grid-cols-1 md:grid-cols-2 border-b border-border">
		<Cell href="#download" class="border-b md:border-b-0 md:border-r border-border flex items-baseline justify-between min-h-[7rem]">
			<span class="text-2xl md:text-3xl font-bold tracking-[-0.03em] text-accent-soft group-hover:text-accent transition-colors">Download .pkg</span>
			<span class="{typography.meta}">macOS 14+</span>
		</Cell>
		<Cell href="/docs/guide/getting-started" class="flex items-baseline justify-between min-h-[7rem]">
			<span class="text-2xl md:text-3xl font-bold tracking-[-0.03em] text-foreground/80 group-hover:text-foreground transition-colors">Docs</span>
			<span class="{typography.meta}">Guide · Protocol</span>
		</Cell>
	</div>

	<!-- Two screenshots, flat, minimal -->
	<div class="grid grid-cols-1 md:grid-cols-2 border-b border-border">
		<div class="border-b md:border-b-0 md:border-r border-border">
			<Cell>
				<Shot src="/screenshots/01-search.png" class="aspect-[3/2]" />
				<p class="mt-4 {typography.meta}">Search</p>
			</Cell>
		</div>
		<div>
			<Cell>
				<Shot src="/screenshots/03-transfers.png" class="aspect-[3/2]" />
				<p class="mt-4 {typography.meta}">Transfers</p>
			</Cell>
		</div>
	</div>

	<!-- Bottom strip -->
	<div class="grid grid-cols-3 min-h-[4.5rem]">
		<Cell pad="sm" class="border-r border-border">
			<span class="text-sm font-bold text-foreground/40">seeleseek</span>
		</Cell>
		<Cell pad="sm" href="https://github.com/bretth18/seeleseek" external class="border-r border-border">
			<span class="text-sm font-bold group-hover:text-accent transition-colors">GitHub</span>
		</Cell>
		<Cell pad="sm">
			<span class="text-sm font-bold text-foreground/40">© 2026</span>
		</Cell>
	</div>

</div>
