// Homepage FAQ — rendered as both JSON-LD (for rich results)
// and a collapsed <details> block at page bottom (accessible + crawlable).

export interface FaqItem {
	q: string;
	a: string;
}

export const homepageFaq: FaqItem[] = [
	{
		q: 'What is seeleseek?',
		a: 'seeleseek is a native Soulseek client for macOS, built in Swift/SwiftUI. It connects to the Soulseek peer-to-peer network for discovering and transferring music between users.'
	},
	{
		q: 'Which macOS versions does seeleseek support?',
		a: 'seeleseek requires macOS 14 Sonoma or later. It runs natively on Apple Silicon and Intel Macs.'
	},
	{
		q: 'Is seeleseek free?',
		a: 'Yes. seeleseek is free to download and use. The source is available on GitHub.'
	},
	{
		q: 'How is seeleseek different from Nicotine+ or SoulseekQt?',
		a: 'seeleseek is written in native Swift and SwiftUI, so it launches instantly, uses system controls, and feels at home on macOS — unlike cross-platform Qt and Python clients.'
	},
	{
		q: 'Does seeleseek work with the official Soulseek network?',
		a: 'Yes. seeleseek speaks the standard Soulseek protocol and connects to server.slsknet.org, the same network used by every other Soulseek client.'
	},
	{
		q: 'Can I share files with seeleseek?',
		a: 'Yes. seeleseek supports browsing, searching, downloading, uploading, chat, and wishlists — everything you would expect from a full Soulseek client.'
	}
];

export function faqJsonLd(items: FaqItem[] = homepageFaq) {
	return {
		'@context': 'https://schema.org',
		'@type': 'FAQPage',
		mainEntity: items.map((item) => ({
			'@type': 'Question',
			name: item.q,
			acceptedAnswer: { '@type': 'Answer', text: item.a }
		}))
	};
}
