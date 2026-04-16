<script lang="ts">
import DitheredImage from '$lib/components/DitheredImage.svelte';
import { Cell, Shot, typography } from '$lib/design';
import { dither } from '$lib/design/tokens';
import { DOWNLOAD_URL, OG_IMAGE, Seo, SITE_DESCRIPTION, SITE_NAME, SITE_URL } from '$lib/seo';
import { faqJsonLd, homepageFaq } from '$lib/seo/faq';

const screenshots = [
	{
		src: '/screenshots/01-search.png',
		label: 'Search',
		alt: 'seeleseek search view showing Soulseek file search results on macOS'
	},
	{
		src: '/screenshots/03-transfers.png',
		label: 'Transfers',
		alt: 'seeleseek transfer queue showing active Soulseek downloads on macOS'
	}
];

const allScreenshots = [
	'01-search',
	'02-wishlists',
	'03-transfers',
	'04-chat',
	'05-browse',
	'06-friends',
	'07-statistics',
	'08-settings'
].map((name) => `${SITE_URL}/screenshots/${name}.png`);

const softwareLd = {
	'@context': 'https://schema.org',
	'@type': 'SoftwareApplication',
	name: SITE_NAME,
	alternateName: ['SeeleSeek', 'seele seek'],
	description: SITE_DESCRIPTION,
	applicationCategory: 'MultimediaApplication',
	applicationSubCategory: 'FileSharingApplication',
	operatingSystem: 'macOS 14+',
	url: SITE_URL,
	downloadUrl: DOWNLOAD_URL,
	image: `${SITE_URL}${OG_IMAGE}`,
	screenshot: allScreenshots,
	softwareVersion: '1.0',
	releaseNotes: `${SITE_URL}/docs/guide/getting-started`,
	offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
	author: { '@type': 'Person', name: 'Brett Henderson', url: 'https://github.com/bretth18' },
	featureList: [
		'Native SwiftUI interface for macOS',
		'Full Soulseek protocol support',
		'Peer-to-peer file search and discovery',
		'Download and upload queue management',
		'User browse and shared file listings',
		'Private chat and room messaging',
		'Wishlists and saved searches',
		'Transfer statistics and history'
	],
	keywords:
		'soulseek, soulseek mac, soulseek macos, native soulseek client, soulseek swiftui, nicotine alternative mac, soulseekqt alternative, peer to peer music'
};
</script>

<Seo description={SITE_DESCRIPTION} jsonLd={[softwareLd, faqJsonLd()]} />

<div class="flex-1 flex flex-col">

	<h2 class="sr-only">Native Soulseek client for macOS</h2>

	<!-- Hero slab -->
	<div class="border-b border-border">
		<Cell pad="lg">
			<div class="flex flex-col gap-12 md:gap-16">
				<DitheredImage
					src="/mascot.svg"
					alt="seeleseek mascot — a native Soulseek client for macOS"
					class="dither-canvas w-28 h-28 md:w-32 md:h-32"
					cutoff={0.5}
					darkrgba={dither.bg}
					lightrgba={dither.accent}
				/>
				<h1 class="{typography.display} text-accent">seeleseek</h1>
				<p class="max-w-xl text-foreground/50 text-[clamp(1rem,1.8vw,1.25rem)] leading-[1.4] tracking-[-0.01em]">
					A Soulseek client for macOS. Built in Swift.
				</p>
			</div>
		</Cell>
	</div>

	<!-- Two-cell action row -->
	<div class="grid grid-cols-1 md:grid-cols-2 border-b border-border">
		<Cell href={DOWNLOAD_URL} external class="border-b md:border-b-0 md:border-r border-border flex items-baseline justify-between min-h-[7rem]">
			<span class="text-2xl md:text-3xl font-bold tracking-[-0.03em] text-accent-soft group-hover:text-accent transition-colors">Download .pkg</span>
			<span class="{typography.meta}">macOS 14+</span>
		</Cell>
		<Cell href="/docs/guide/getting-started" class="flex items-baseline justify-between min-h-[7rem]">
			<span class="text-2xl md:text-3xl font-bold tracking-[-0.03em] text-foreground/80 group-hover:text-foreground transition-colors">Docs</span>
			<span class="{typography.meta}">Guide · Protocol</span>
		</Cell>
	</div>

	<!-- Two screenshots, flat, minimal -->
	<h2 class="sr-only">Screenshots</h2>
	<div class="grid grid-cols-1 md:grid-cols-2 border-b border-border">
		{#each screenshots as shot, i}
			<div class={i === 0 ? 'border-b md:border-b-0 md:border-r border-border' : ''}>
				<Cell>
					<Shot src={shot.src} alt={shot.alt} class="aspect-[3/2]" />
					<p class="mt-4 {typography.meta}">{shot.label}</p>
				</Cell>
			</div>
		{/each}
	</div>

	<!-- FAQ — collapsed, accessible, crawlable -->
	<section class="border-b border-border" aria-labelledby="faq-heading">
		<Cell pad="md">
			<h2 id="faq-heading" class="{typography.meta} mb-4">FAQ</h2>
			<div class="flex flex-col">
				{#each homepageFaq as item}
					<details class="group border-t border-border first:border-t-0 py-3">
						<summary class="cursor-pointer list-none flex items-baseline justify-between gap-4 text-sm font-bold tracking-[-0.01em] text-foreground/80 hover:text-foreground transition-colors">
							<span>{item.q}</span>
							<span class="text-foreground/30 group-open:text-accent transition-colors" aria-hidden="true">+</span>
						</summary>
						<p class="mt-3 text-sm text-foreground/50 leading-[1.5] max-w-2xl">{item.a}</p>
					</details>
				{/each}
			</div>
		</Cell>
	</section>

	<!-- Bottom strip -->
	<div class="grid grid-cols-3 min-h-[4.5rem]">
		<Cell pad="sm" class="border-r border-border">
			<span class="text-sm font-bold text-foreground/40">seeleseek</span>
		</Cell>
		<Cell pad="sm" href="https://github.com/bretth18/seeleseek" external class="border-r border-border">
			<span class="text-sm font-bold group-hover:text-accent transition-colors">GitHub</span>
		</Cell>
		<Cell pad="sm">
			<span class="text-sm font-bold text-foreground/40">©2026 seeleseek</span>
		</Cell>
	</div>

</div>
