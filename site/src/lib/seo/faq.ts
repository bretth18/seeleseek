// Homepage FAQ — rendered as both JSON-LD (for rich results)
// and a collapsed <details> block at page bottom (accessible + crawlable).

export interface FaqItem {
	q: string;
	a: string;
}

export const homepageFaq: FaqItem[] = [
	{
		q: 'What is seeleseek?',
		a: 'seeleseek is a native Soulseek client for macOS, written in Swift and SwiftUI. It connects to the Soulseek peer-to-peer network, where users find and transfer music.'
	},
	{
		q: 'Which macOS versions does seeleseek support?',
		a: 'seeleseek operates on macOS 15.6 or later. It is a native app for Apple Silicon and Intel Macs.'
	},
	{
		q: 'Is seeleseek free?',
		a: 'Yes. The download and the use of seeleseek are free. The source code is available on GitHub.'
	},
	{
		q: 'How is seeleseek different from Nicotine+ or SoulseekQt?',
		a: 'seeleseek is written in native Swift and SwiftUI. It starts quickly, uses the system controls, and has the standard macOS look. Cross-platform Qt and Python clients do not.'
	},
	{
		q: 'Does seeleseek work with the official Soulseek network?',
		a: 'Yes. seeleseek uses the standard Soulseek protocol. It connects to server.slsknet.org, the same server that all other Soulseek clients use.'
	},
	{
		q: 'Can I share files with seeleseek?',
		a: 'Yes. seeleseek has browse, search, download, upload, chat, and wishlist functions. It is a full Soulseek client.'
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
