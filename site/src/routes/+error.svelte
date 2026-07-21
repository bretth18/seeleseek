<script lang="ts">
import { page } from '$app/state';
import NotFound from '$lib/components/NotFound.svelte';
import { Seo } from '$lib/seo';

const status = $derived(page.status);
const isNotFound = $derived(status === 404);
const message = $derived(
	isNotFound ? 'This page does not exist.' : (page.error?.message ?? 'An error occurred.')
);
</script>

<Seo
	title={isNotFound ? '404' : `${status}`}
	description={isNotFound ? 'This page does not exist.' : 'An error occurred.'}
	noindex
/>

<NotFound {status} {message} />
