<script lang="ts">
import NotFound from '$lib/components/NotFound.svelte';
import { Seo } from '$lib/seo';

export const prerender = true;
</script>

<Seo title="404" description="page not found" noindex />

<NotFound status={404} message="page not found" />
