<script lang="ts">
import { page } from '$app/state';
import NotFound from '$lib/components/NotFound.svelte';
import { Seo } from '$lib/seo';

const status = $derived(page.status);
const isNotFound = $derived(status === 404);
const message = $derived(
	isNotFound ? 'page not found' : (page.error?.message ?? 'something broke')
);
</script>

<Seo
	title={isNotFound ? '404' : `${status}`}
	description={isNotFound ? 'page not found' : 'something broke'}
	noindex
/>

<NotFound {status} {message} />
