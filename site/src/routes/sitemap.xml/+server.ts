import { SITE_URL } from '$lib/seo/site';
import { getDocPages } from '$lib/utils/docs';

export const prerender = true;

export const GET = async () => {
	const docPages = getDocPages();
	const staticPaths = ['/', '/docs'];
	const docPaths = docPages.map((p) => `/docs/${p.slug}`);
	const all = [...staticPaths, ...docPaths];

	const now = new Date().toISOString().split('T')[0];
	const urls = all
		.map(
			(path) => `	<url>
		<loc>${SITE_URL}${path}</loc>
		<lastmod>${now}</lastmod>
		<changefreq>weekly</changefreq>
		<priority>${path === '/' ? '1.0' : '0.7'}</priority>
	</url>`
		)
		.join('\n');

	const body = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls}
</urlset>`;

	return new Response(body, {
		headers: { 'content-type': 'application/xml; charset=utf-8' }
	});
};
