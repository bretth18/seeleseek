<script lang="ts">
import { page } from '$app/state';
import { OG_IMAGE, SITE_DESCRIPTION, SITE_NAME, SITE_TWITTER, SITE_URL } from './site';

interface Props {
	title?: string;
	description?: string;
	image?: string;
	type?: 'website' | 'article';
	noindex?: boolean;
	jsonLd?: Record<string, unknown> | Record<string, unknown>[];
}

let {
	title,
	description = SITE_DESCRIPTION,
	image = OG_IMAGE,
	type = 'website',
	noindex = false,
	jsonLd
}: Props = $props();

const fullTitle = $derived(title ? `${title} — ${SITE_NAME}` : SITE_NAME);
const canonical = $derived(`${SITE_URL}${page.url.pathname}`);
const absImage = $derived(image.startsWith('http') ? image : `${SITE_URL}${image}`);
const ldString = $derived(jsonLd ? JSON.stringify(jsonLd) : null);
</script>

<svelte:head>
	<title>{fullTitle}</title>
	<meta name="description" content={description} />
	<link rel="canonical" href={canonical} />
	{#if noindex}
		<meta name="robots" content="noindex,nofollow" />
	{/if}

	<meta property="og:type" content={type} />
	<meta property="og:site_name" content={SITE_NAME} />
	<meta property="og:title" content={fullTitle} />
	<meta property="og:description" content={description} />
	<meta property="og:url" content={canonical} />
	<meta property="og:image" content={absImage} />
	<meta property="og:image:width" content="1200" />
	<meta property="og:image:height" content="630" />

	<meta name="twitter:card" content="summary_large_image" />
	<meta name="twitter:site" content={SITE_TWITTER} />
	<meta name="twitter:creator" content={SITE_TWITTER} />
	<meta name="twitter:title" content={fullTitle} />
	<meta name="twitter:description" content={description} />
	<meta name="twitter:image" content={absImage} />

	{#if ldString}
		{@html `<script type="application/ld+json">${ldString}<` + `/script>`}
	{/if}
</svelte:head>
