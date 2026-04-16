<script lang="ts">
import { onDestroy, onMount } from 'svelte';
import { browser } from '$app/environment';
import DitherWorker from '$lib/workers/dither.worker?worker';

interface Props {
	src: string;
	alt: string;
	crunch?: number | 'auto' | 'pixel';
	cutoff?: number;
	darkrgba?: [number, number, number, number];
	lightrgba?: [number, number, number, number];
	class?: string;
}

let {
	src,
	alt,
	crunch = 'auto',
	cutoff = 0.5,
	darkrgba = [0, 0, 0, 255],
	lightrgba = [255, 255, 255, 255],
	class: className = ''
}: Props = $props();

let canvas: HTMLCanvasElement | undefined = $state();
let containerDiv: HTMLDivElement | undefined = $state();
let worker: Worker | undefined = $state();
let ctx: CanvasRenderingContext2D | null = null;
let originalImage: HTMLImageElement | undefined = $state();
let imageLoading = $state(false);
let needsUpdate = $state(false);

let resizingTimeout: ReturnType<typeof setTimeout> | undefined;
let ignoreNextResize = false;
let resizeObserver: ResizeObserver | undefined;
let intersectionObserver: IntersectionObserver | undefined;
let animationFrameId: number | undefined;

let lastDrawState = {
	width: 0,
	height: 0,
	adjustedPixelSize: 0,
	imageSrc: '',
	cutoff: 0,
	darkrgba: [0, 0, 0, 255] as [number, number, number, number],
	lightrgba: [255, 255, 255, 255] as [number, number, number, number]
};

let crunchFactor = $derived(
	crunch === 'auto'
		? getAutoCrunchFactor()
		: crunch === 'pixel'
			? 1.0 / getDevicePixelRatio()
			: typeof crunch === 'number'
				? crunch
				: getAutoCrunchFactor()
);

function getAutoCrunchFactor(): number {
	if (!browser) return 1;
	return getDevicePixelRatio() < 3 ? 1 : 2;
}

function getDevicePixelRatio(): number {
	if (!browser) return 1;
	return window.devicePixelRatio || 1;
}

function isInOrNearViewport(): boolean {
	if (!browser || !containerDiv) return true;

	const margin = 1500;
	const r = containerDiv.getBoundingClientRect();
	const viewHeight = Math.max(document.documentElement.clientHeight, window.innerHeight);
	const above = r.bottom + margin < 0;
	const below = r.top - margin > viewHeight;

	return !above && !below;
}

async function loadImage() {
	if (imageLoading || !browser) {
		return;
	}

	imageLoading = true;
	const image = new Image();

	// Enable CORS for remote images
	image.crossOrigin = 'anonymous';
	image.src = src;

	try {
		await image.decode();
		originalImage = image;
		ignoreNextResize = true;
		if (canvas) {
			canvas.style.aspectRatio = `${image.width} / ${image.height}`;
		}
		needsUpdate = true;
	} catch (error) {
		console.error('Error loading image:', error);
		originalImage = undefined;
	} finally {
		imageLoading = false;
	}
}

function repaintImage() {
	if (!browser || !canvas || !originalImage || !ctx) {
		return;
	}

	const rect = canvas.getBoundingClientRect();

	if (rect.width === 0 || rect.height === 0) {
		return;
	}

	let screenPixelsToBackingStorePixels = getDevicePixelRatio();
	let fractionalPart =
		screenPixelsToBackingStorePixels - Math.floor(screenPixelsToBackingStorePixels);

	let currentCrunchFactor = crunchFactor;
	if (crunch === 'pixel') {
		currentCrunchFactor = 1.0 / getDevicePixelRatio();
	}

	if (1.0 / fractionalPart > 3) {
		fractionalPart = 0;
		screenPixelsToBackingStorePixels = Math.round(screenPixelsToBackingStorePixels);
	}
	if (fractionalPart !== 0) {
		screenPixelsToBackingStorePixels = Math.round(
			screenPixelsToBackingStorePixels * Math.round(1.0 / fractionalPart)
		);
	}

	const calculatedWidth = Math.round(rect.width * screenPixelsToBackingStorePixels);
	const calculatedHeight = Math.round(rect.height * screenPixelsToBackingStorePixels);
	const adjustedPixelSize = Math.round(screenPixelsToBackingStorePixels * currentCrunchFactor);

	// Check if we need to redraw
	if (
		lastDrawState.width === calculatedWidth &&
		lastDrawState.height === calculatedHeight &&
		lastDrawState.adjustedPixelSize === adjustedPixelSize &&
		lastDrawState.imageSrc === originalImage.currentSrc &&
		lastDrawState.cutoff === cutoff &&
		JSON.stringify(lastDrawState.darkrgba) === JSON.stringify(darkrgba) &&
		JSON.stringify(lastDrawState.lightrgba) === JSON.stringify(lightrgba)
	) {
		needsUpdate = false;
		return;
	}

	canvas.width = calculatedWidth;
	canvas.height = calculatedHeight;

	lastDrawState = {
		width: calculatedWidth,
		height: calculatedHeight,
		adjustedPixelSize,
		imageSrc: originalImage.currentSrc,
		cutoff,
		darkrgba: [...darkrgba],
		lightrgba: [...lightrgba]
	};

	const drawWidth = canvas.width / adjustedPixelSize;
	const drawHeight = canvas.height / adjustedPixelSize;

	ctx.imageSmoothingEnabled = true;
	ctx.drawImage(originalImage, 0, 0, drawWidth, drawHeight);

	const originalData = ctx.getImageData(0, 0, drawWidth, drawHeight);
	ctx.clearRect(0, 0, canvas.width, canvas.height);

	if (worker) {
		worker.postMessage({
			imageData: originalData,
			pixelSize: adjustedPixelSize,
			cutoff,
			blackRGBA: darkrgba,
			whiteRGBA: lightrgba
		});
	}

	needsUpdate = false;
}

function scheduleUpdate() {
	if (animationFrameId !== undefined) {
		return; // Already scheduled
	}

	animationFrameId = window.requestAnimationFrame(() => {
		animationFrameId = undefined;

		if (!needsUpdate) {
			return;
		}

		if (!originalImage) {
			loadImage();
			return;
		}

		if (isInOrNearViewport()) {
			repaintImage();
		}
	});
}

onMount(() => {
	if (!browser) return;

	worker = new DitherWorker();

	worker.onmessage = (e) => {
		if (canvas && ctx) {
			ctx.putImageData(e.data.imageData, 0, 0);
		}
	};

	worker.onerror = (e) => {
		console.error('Worker error:', e);
	};

	// Get context once
	if (canvas) {
		ctx = canvas.getContext('2d', { willReadFrequently: true });

		// ResizeObserver
		resizeObserver = new ResizeObserver((entries) => {
			if (entries.length > 0 && entries[0].contentBoxSize) {
				if (ignoreNextResize) {
					ignoreNextResize = false;
					return;
				}

				if (resizingTimeout) {
					clearTimeout(resizingTimeout);
				}

				resizingTimeout = setTimeout(() => {
					resizingTimeout = undefined;
					needsUpdate = true;
					scheduleUpdate();
				}, 200);
			}
		});
		resizeObserver.observe(canvas);
	}

	// IntersectionObserver
	if (containerDiv) {
		intersectionObserver = new IntersectionObserver(
			(intersections) => {
				if (intersections.length > 0 && intersections[0].isIntersecting) {
					needsUpdate = true;
					scheduleUpdate();
				}
			},
			{ root: null, rootMargin: '1000px', threshold: [0] }
		);
		intersectionObserver.observe(containerDiv);
	}

	needsUpdate = true;
	scheduleUpdate();

	return () => {
		resizeObserver?.disconnect();
		intersectionObserver?.disconnect();
		if (animationFrameId !== undefined) {
			cancelAnimationFrame(animationFrameId);
		}
	};
});

onDestroy(() => {
	worker?.terminate();
	if (resizingTimeout) {
		clearTimeout(resizingTimeout);
	}
});

// Watch for src changes - this should only trigger when src actually changes
$effect(() => {
	const currentSrc = src; // Track the dependency
	if (browser && currentSrc) {
		originalImage = undefined;
		needsUpdate = true;
		scheduleUpdate();
	}
});

// Watch for property changes - only trigger when these specific values change
$effect(() => {
	if (browser) {
		// These are the dependencies we're tracking
		const _crunch = crunch;
		const _cutoff = cutoff;
		const _darkrgba = darkrgba;
		const _lightrgba = lightrgba;

		// Only update if we have an image
		if (originalImage) {
			needsUpdate = true;
			scheduleUpdate();
		}
	}
});
</script>

<div bind:this={containerDiv} class={className}>
    <canvas
        bind:this={canvas}
        aria-label={alt}
        class="w-full h-full"
        style="image-rendering: crisp-edges;"
    ></canvas>
</div>
