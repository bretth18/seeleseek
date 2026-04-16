<script lang="ts">
import DitheredImage from '$lib/components/DitheredImage.svelte';
import { Cell, typography } from '$lib/design';
import { dither } from '$lib/design/tokens';

interface Props {
	status?: number;
	message?: string;
}

let { status = 404, message = 'page not found' }: Props = $props();
</script>

<div class="flex-1 flex flex-col">
	<div class="border-b border-border">
		<Cell pad="lg">
			<div class="flex flex-col gap-12 md:gap-16">
				<DitheredImage
					src="/mascot.svg"
					alt=""
					class="dither-canvas w-28 h-28 md:w-32 md:h-32 opacity-40"
					cutoff={0.5}
					darkrgba={dither.bg}
					lightrgba={dither.fg}
				/>
				<h1 class="{typography.display} text-accent">{status}</h1>
				<p
					class="max-w-xl text-foreground/50 text-[clamp(1rem,1.8vw,1.25rem)] leading-[1.4] tracking-[-0.01em]"
				>
					{message}
				</p>
			</div>
		</Cell>
	</div>

	<div class="grid grid-cols-1 md:grid-cols-2 border-b border-border">
		<Cell
			href="/"
			class="border-b md:border-b-0 md:border-r border-border flex items-baseline justify-between min-h-[7rem]"
		>
			<span
				class="text-2xl md:text-3xl font-bold tracking-[-0.03em] text-accent-soft group-hover:text-accent transition-colors"
				>Home</span
			>
			<span class="{typography.meta}">/</span>
		</Cell>
		<Cell
			href="/docs/guide/getting-started"
			class="flex items-baseline justify-between min-h-[7rem]"
		>
			<span
				class="text-2xl md:text-3xl font-bold tracking-[-0.03em] text-foreground/80 group-hover:text-foreground transition-colors"
				>Docs</span
			>
			<span class="{typography.meta}">/docs</span>
		</Cell>
	</div>
</div>
