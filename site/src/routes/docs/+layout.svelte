<script lang="ts">
import DocsMobileNav from '$lib/components/DocsMobileNav.svelte';
import Sidebar from '$lib/components/Sidebar.svelte';

let { data, children } = $props();
</script>

<DocsMobileNav sections={data.sections} />

<div class="mx-auto flex max-w-6xl gap-10 px-5 md:px-10 py-8">
	<div class="hidden lg:block">
		<Sidebar sections={data.sections} />
	</div>
	<div class="min-w-0 flex-1">
		{@render children()}
	</div>
</div>
