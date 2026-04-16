<script lang="ts">
import type { Snippet } from 'svelte';
import { typography } from './tokens';

interface Props {
	class?: string;
	children: Snippet;
}

let { class: className = '', children }: Props = $props();
</script>

<p class="{typography.eyebrow} {className}">{@render children()}</p>
