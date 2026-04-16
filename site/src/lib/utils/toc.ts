export interface TocEntry {
	id: string;
	text: string;
	level: number;
}

export function extractToc(html: string): TocEntry[] {
	const entries: TocEntry[] = [];
	const regex = /<h([2-3])\s+id="([^"]+)"[^>]*>(.*?)<\/h[2-3]>/g;
	let match: RegExpExecArray | null = regex.exec(html);

	while (match !== null) {
		const text = match[3].replace(/<[^>]+>/g, '').trim();
		entries.push({
			level: parseInt(match[1]),
			id: match[2],
			text
		});
		match = regex.exec(html);
	}

	return entries;
}
