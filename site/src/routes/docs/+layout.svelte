<script lang="ts">
	import Sidebar from '$lib/components/Sidebar.svelte';

	let { data, children } = $props();
</script>

<div class="mx-auto flex max-w-6xl gap-10 px-5 md:px-10 py-8">
	<Sidebar sections={data.sections} />
	<div class="min-w-0 flex-1">
		{@render children()}
	</div>
</div>
