<script lang="ts">
import type { Snippet } from 'svelte';
import Container from './Container.svelte';
import { section } from './tokens';

type Spacing = keyof typeof section;

interface Props {
	id?: string;
	spacing?: Spacing;
	divider?: boolean;
	class?: string;
	children: Snippet;
}

let { id, spacing = 'base', divider = true, class: className = '', children }: Props = $props();
</script>

<section {id} class="{divider ? 'border-t border-border' : ''} {className}">
	<Container class={section[spacing]}>
		{@render children()}
	</Container>
</section>
