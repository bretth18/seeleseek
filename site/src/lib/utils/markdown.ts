import rehypeAutolinkHeadings from 'rehype-autolink-headings';
import rehypeSlug from 'rehype-slug';
import rehypeStringify from 'rehype-stringify';
import remarkGfm from 'remark-gfm';
import remarkParse from 'remark-parse';
import remarkRehype from 'remark-rehype';
import { unified } from 'unified';

export interface DocFrontmatter {
	title: string;
	description: string;
	order: number;
	category?: string;
}

const processor = unified()
	.use(remarkParse)
	.use(remarkGfm)
	.use(remarkRehype)
	.use(rehypeSlug)
	.use(rehypeAutolinkHeadings, { behavior: 'wrap' })
	.use(rehypeStringify);

export function parseFrontmatter(raw: string): { frontmatter: DocFrontmatter; content: string } {
	const match = raw.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
	if (!match) {
		return {
			frontmatter: { title: '', description: '', order: 999 },
			content: raw
		};
	}

	const frontmatter: Record<string, string | number> = {};
	for (const line of match[1].split('\n')) {
		const idx = line.indexOf(':');
		if (idx === -1) continue;
		const key = line.slice(0, idx).trim();
		let value: string | number = line.slice(idx + 1).trim();
		if (/^\d+$/.test(value)) value = parseInt(value);
		frontmatter[key] = value;
	}

	return {
		frontmatter: {
			title: (frontmatter.title as string) || '',
			description: (frontmatter.description as string) || '',
			order: (frontmatter.order as number) || 999,
			category: frontmatter.category as string | undefined
		},
		content: match[2]
	};
}

export async function renderMarkdown(source: string): Promise<string> {
	const result = await processor.process(source);
	return String(result);
}
