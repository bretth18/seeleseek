<script lang="ts">
import DitheredImage from '$lib/components/DitheredImage.svelte';
import { Cell, typography } from '$lib/design';
import { dither } from '$lib/design/tokens';
import { DOWNLOAD_URL, OG_IMAGE, Seo, SITE_DESCRIPTION, SITE_NAME, SITE_URL } from '$lib/seo';
import { faqJsonLd, homepageFaq } from '$lib/seo/faq';

const screenshot = {
	src: '/screenshots/03-transfers.png',
	alt: "seeleseek downloading several files in various states on macOS"
};

const faqColumns = [
	homepageFaq.slice(0, Math.ceil(homepageFaq.length / 2)),
	homepageFaq.slice(Math.ceil(homepageFaq.length / 2))
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
	operatingSystem: 'macOS 15.6+',
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


	<div class="grid grid-cols-1 lg:grid-cols-2 lg:min-h-[max(22rem,calc(100svh-29rem))] border-b border-border">
		<Cell pad="md" class="border-b lg:border-b-0 lg:border-r border-border lg:flex lg:flex-col lg:justify-center">
			<div class="flex flex-col gap-6 md:gap-8">
				<DitheredImage
					src="/mascot.svg"
					alt="seeleseek mascot — a native Soulseek client for macOS"
					class="dither-canvas w-20 h-20 md:w-24 md:h-24"
					cutoff={0.5}
					darkrgba={dither.bg}
					lightrgba={dither.accent}
				/>
				<div class="flex flex-col gap-4 md:gap-6">
					<h1 class="{typography.display} text-accent">seeleseek</h1>
					<p class="max-w-xl text-foreground/60 text-[clamp(1rem,1.8vw,1.25rem)] leading-[1.4] tracking-[-0.01em]">
						A native Soulseek client for macOS, written in Swift.
					</p>
				</div>
			</div>
		</Cell>


		<div class="relative overflow-hidden aspect-2206/1100 sm:aspect-2206/900 lg:aspect-auto">
			<h2 class="sr-only">Screenshots</h2>
			<div class="@container absolute inset-x-5 top-6 md:inset-x-10 md:top-8 lg:bottom-0 lg:right-0 lg:@container-[size]">
				<img src={screenshot.src} alt={screenshot.alt} width="2206" height="1340" fetchpriority="high" decoding="async" class="w-full h-auto rounded-t-[2.6cqw] lg:h-full lg:object-cover lg:object-left-top lg:rounded-none lg:rounded-l-[calc(max(100cqw,164.6cqh)*0.0249)]" />
			</div>
		</div>
	</div>

	<!-- Two-cell action row -->
	<div class="grid grid-cols-1 lg:grid-cols-2 border-b border-border">
		<Cell href={DOWNLOAD_URL} external class="border-b lg:border-b-0 lg:border-r border-border flex items-baseline justify-between">
			<span class="text-2xl md:text-3xl font-bold tracking-[-0.03em] text-foreground group-hover:text-accent transition-colors">Download .pkg</span>
			<span class="{typography.meta}">macOS 15.6+</span>
		</Cell>
		<Cell href="/docs/guide/getting-started" class="flex items-baseline justify-between">
			<span class="text-2xl md:text-3xl font-bold tracking-[-0.03em] text-foreground/80 group-hover:text-foreground transition-colors">Docs</span>
			<span class="{typography.meta}">Guide · Protocol</span>
		</Cell>
	</div>


	<section class="flex-1" aria-labelledby="faq-heading">
		<h2 id="faq-heading" class="{typography.meta} px-5 md:px-10 pt-6 md:pt-8 pb-3">FAQ</h2>
		<div class="grid grid-cols-1 lg:grid-cols-2">
			{#each faqColumns as column, i}
				<div class="px-5 md:px-10 {i === 0 ? 'lg:border-r border-border lg:pb-8' : 'pb-6 md:pb-8'}">
					{#each column as item, j}
						<details class="group py-3 {j > 0 || i > 0 ? 'border-t border-border' : ''} {i > 0 && j === 0 ? 'lg:border-t-0' : ''}">
							<summary class="cursor-pointer list-none flex items-baseline justify-between gap-4 text-sm font-bold tracking-[-0.01em] text-foreground/80 hover:text-foreground transition-colors">
								<span>{item.q}</span>
								<span class="text-foreground/40 group-open:text-accent transition-colors" aria-hidden="true">+</span>
							</summary>
							<p class="mt-3 text-sm text-foreground/60 leading-normal max-w-2xl">{item.a}</p>
						</details>
					{/each}
				</div>
			{/each}
		</div>
	</section>

	<footer class="border-t border-border grid grid-cols-2">
		<Cell pad="sm" class="border-r border-border">
			<span class="text-sm text-foreground/55">©2026 seeleseek</span>
		</Cell>
		<Cell pad="sm" href="https://github.com/bretth18/seeleseek" external>
			<span class="text-sm font-bold group-hover:text-accent transition-colors">GitHub ↗</span>
		</Cell>
	</footer>

</div>
