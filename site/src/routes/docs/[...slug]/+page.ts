import { error } from '@sveltejs/kit';
import { getAdjacentPages, getDocPages } from '$lib/utils/docs';
import { parseFrontmatter, renderMarkdown } from '$lib/utils/markdown';
import type { PageLoad } from './$types';

const modules = import.meta.glob('/src/content/docs/**/*.md', {
	query: '?raw',
	import: 'default'
});

export const load: PageLoad = async ({ params }) => {
	const slug = params.slug;
	const key = `/src/content/docs/${slug}.md`;
	const loader = modules[key];

	if (!loader) {
		error(404, `Doc page "${slug}" not found`);
	}

	const raw = (await loader()) as string;
	const { frontmatter, content } = parseFrontmatter(raw);
	const html = await renderMarkdown(content);

	const allPages = getDocPages();
	const { prev, next } = getAdjacentPages(allPages, slug);

	return {
		meta: frontmatter,
		html,
		prev,
		next
	};
};
