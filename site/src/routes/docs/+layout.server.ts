import { getDocPages, groupBySections } from '$lib/utils/docs';
import type { LayoutServerLoad } from './$types';

export const load: LayoutServerLoad = async () => {
	const pages = getDocPages();
	const sections = groupBySections(pages);
	return { pages, sections };
};
