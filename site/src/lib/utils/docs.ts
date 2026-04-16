import { parseFrontmatter } from './markdown';

export interface DocPage {
	slug: string;
	title: string;
	description: string;
	order: number;
	section: string;
}

export interface DocSection {
	name: string;
	slug: string;
	order: number;
	pages: DocPage[];
}

const sectionMeta: Record<string, { label: string; order: number }> = {
	guide: { label: 'User Guide', order: 1 },
	package: { label: 'Package API', order: 2 }
};

export function getDocPages(): DocPage[] {
	const modules = import.meta.glob('/src/content/docs/**/*.md', {
		eager: true,
		query: '?raw',
		import: 'default'
	}) as Record<string, string>;

	const pages: DocPage[] = [];

	for (const [path, raw] of Object.entries(modules)) {
		// path like /src/content/docs/guide/getting-started.md
		const relative = path.replace('/src/content/docs/', '').replace('.md', '');
		const parts = relative.split('/');
		const section = parts.length > 1 ? parts[0] : 'general';
		const { frontmatter } = parseFrontmatter(raw);

		pages.push({
			slug: relative,
			title: frontmatter.title || parts[parts.length - 1],
			description: frontmatter.description || '',
			order: frontmatter.order,
			section
		});
	}

	return pages.sort((a, b) => a.order - b.order);
}

export function groupBySections(pages: DocPage[]): DocSection[] {
	const sectionMap = new Map<string, DocPage[]>();

	for (const page of pages) {
		if (!sectionMap.has(page.section)) {
			sectionMap.set(page.section, []);
		}
		sectionMap.get(page.section)!.push(page);
	}

	const sections: DocSection[] = [];
	for (const [slug, sectionPages] of sectionMap) {
		const meta = sectionMeta[slug] || { label: slug, order: 99 };
		sections.push({
			name: meta.label,
			slug,
			order: meta.order,
			pages: sectionPages.sort((a, b) => a.order - b.order)
		});
	}

	return sections.sort((a, b) => a.order - b.order);
}

export function getAdjacentPages(
	pages: DocPage[],
	currentSlug: string
): { prev: DocPage | null; next: DocPage | null } {
	const idx = pages.findIndex((p) => p.slug === currentSlug);
	return {
		prev: idx > 0 ? pages[idx - 1] : null,
		next: idx < pages.length - 1 ? pages[idx + 1] : null
	};
}
