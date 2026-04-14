interface DitherMessage {
	imageData: ImageData;
	pixelSize: number;
	cutoff: number;
	blackRGBA: [number, number, number, number];
	whiteRGBA: [number, number, number, number];
}

interface DitherResponse {
	imageData: ImageData;
	pixelSize: number;
	cutoff: number;
}

function getRGBAArrayBuffer(
	color: [number, number, number, number],
): Uint8ClampedArray {
	const buffer = new Uint8ClampedArray(4);
	for (let i = 0; i < 4; ++i) {
		buffer[i] = color[i];
	}
	return buffer;
}

function dither(
	imageData: ImageData,
	scaleFactor: number,
	cutoff: number,
	blackRGBA: [number, number, number, number],
	whiteRGBA: [number, number, number, number],
): ImageData {
	// console.log("Worker: Starting dither process", {
	// 	width: imageData.width,
	// 	height: imageData.height,
	// 	scaleFactor,
	// 	cutoff,
	// });

	const blackRGBABuffer = getRGBAArrayBuffer(blackRGBA);
	const whiteRGBABuffer = getRGBAArrayBuffer(whiteRGBA);
	const output = new ImageData(
		imageData.width * scaleFactor,
		imageData.height * scaleFactor,
	);

	// Convert to grayscale
	for (let i = 0; i < imageData.data.length; i += 4) {
		imageData.data[i] =
			imageData.data[i + 1] =
			imageData.data[i + 2] =
				Math.floor(
					imageData.data[i] * 0.3 +
						imageData.data[i + 1] * 0.59 +
						imageData.data[i + 2] * 0.11,
				);
	}

	const slidingErrorWindow: Float32Array[] = [
		new Float32Array(imageData.width),
		new Float32Array(imageData.width),
		new Float32Array(imageData.width),
	];
	const offsets: [number, number][] = [
		[1, 0],
		[2, 0],
		[-1, 1],
		[0, 1],
		[1, 1],
		[0, 2],
	];

	for (let y = 0, limY = imageData.height; y < limY; ++y) {
		for (let x = 0, limX = imageData.width; x < limX; ++x) {
			const i = (y * limX + x) * 4;
			const accumulatedError = Math.floor(slidingErrorWindow[0][x]);
			const expectedMono = imageData.data[i] + accumulatedError;
			const monoValue = expectedMono <= Math.floor(cutoff * 255) ? 0 : 255;
			const error = (expectedMono - monoValue) / 8.0;

			for (let q = 0; q < offsets.length; ++q) {
				const offsetX = offsets[q][0] + x;
				const offsetY = offsets[q][1];
				if (offsetX >= 0 && offsetX < slidingErrorWindow[0].length) {
					slidingErrorWindow[offsetY][offsetX] += error;
				}
			}

			const rgba = monoValue === 0 ? blackRGBABuffer : whiteRGBABuffer;

			for (let scaleY = 0; scaleY < scaleFactor; ++scaleY) {
				let pixelOffset =
					((y * scaleFactor + scaleY) * output.width + x * scaleFactor) * 4;
				for (let scaleX = 0; scaleX < scaleFactor; ++scaleX) {
					output.data[pixelOffset] = rgba[0];
					output.data[pixelOffset + 1] = rgba[1];
					output.data[pixelOffset + 2] = rgba[2];
					output.data[pixelOffset + 3] = rgba[3];
					pixelOffset += 4;
				}
			}
		}

		slidingErrorWindow.push(slidingErrorWindow.shift()!);
		slidingErrorWindow[2].fill(0, 0, slidingErrorWindow[2].length);
	}

	// console.log("Worker: Dither complete", {
	// 	outputWidth: output.width,
	// 	outputHeight: output.height,
	// });

	return output;
}

self.onmessage = (e: MessageEvent<DitherMessage>) => {
	// console.log('Worker: Received message', e.data);
	const result = dither(
		e.data.imageData,
		e.data.pixelSize,
		e.data.cutoff,
		e.data.blackRGBA,
		e.data.whiteRGBA,
	);

	const reply: DitherResponse = {
		imageData: result,
		pixelSize: e.data.pixelSize,
		cutoff: e.data.cutoff,
	};

	self.postMessage(reply);
	// console.log("Worker: Sent reply");
};

export {};
