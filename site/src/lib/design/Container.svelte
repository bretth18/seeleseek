<script lang="ts">
	import type { Snippet } from 'svelte';
	import { container } from './tokens';

	interface Props {
		class?: string;
		children: Snippet;
	}

	let { class: className = '', children }: Props = $props();
</script>

<div class="{container} {className}">
	{@render children()}
</div>
