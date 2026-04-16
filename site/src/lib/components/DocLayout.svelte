

<script lang="ts">
import type { Snippet } from 'svelte';
import { page } from '$app/state';
import { Seo, SITE_NAME, SITE_URL } from '$lib/seo';

interface DocMetadata {
	title: string;
	description: string;
	order: number;
	category?: string;
	layout: string;
}

let {
	title,
	description,
	children
}: {
	title: string;
	description: string;
	children: Snippet;
} = $props();

const crumbs = $derived.by(() => {
	const parts = page.url.pathname.split('/').filter(Boolean);
	const items = [{ name: SITE_NAME, path: '/' }];
	let acc = '';
	for (const p of parts) {
		acc += `/${p}`;
		items.push({ name: p === 'docs' ? 'Docs' : p.replace(/-/g, ' '), path: acc });
	}
	return items;
});

const breadcrumbLd = $derived({
	'@context': 'https://schema.org',
	'@type': 'BreadcrumbList',
	itemListElement: crumbs.map((c, i) => ({
		'@type': 'ListItem',
		position: i + 1,
		name: c.name,
		item: `${SITE_URL}${c.path}`
	}))
});

const articleLd = $derived({
	'@context': 'https://schema.org',
	'@type': 'TechArticle',
	headline: title,
	description,
	url: `${SITE_URL}${page.url.pathname}`,
	author: { '@type': 'Person', name: 'Brett Henderson', url: 'https://github.com/bretth18' },
	publisher: { '@type': 'Organization', name: SITE_NAME, url: SITE_URL }
});
</script>

<Seo title={`${title} · docs`} {description} type="article" jsonLd={[articleLd, breadcrumbLd]} />

<article class="prose prose-invert max-w-none" data-pagefind-body>
	<p class="text-xs font-mono text-muted-foreground tracking-tighter not-prose mb-2">
		// {description}
	</p>
	<h1 class="tracking-tighter">{title}</h1>
	{@render children()}
</article>
