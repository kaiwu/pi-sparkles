import { deflateSync } from "node:zlib";

export function render(planJson) {
  const plan = JSON.parse(planJson);
  const width = checkedInteger(plan.width, 64, 1200, "width");
  const height = checkedInteger(plan.height, 64, 1200, "height");
  if (!Array.isArray(plan.primitives) || plan.primitives.length > 10000) {
    throw new Error("invalid bounded render primitive list");
  }

  const pixels = new Uint8Array(width * height * 4);
  const background = color(plan.background);
  for (let offset = 0; offset < pixels.length; offset += 4) {
    pixels[offset] = background[0];
    pixels[offset + 1] = background[1];
    pixels[offset + 2] = background[2];
    pixels[offset + 3] = 255;
  }

  for (const primitive of plan.primitives) {
    const ink = color(primitive.color);
    if (primitive.kind === "line") {
      line(
        pixels,
        width,
        height,
        checkedCoordinate(primitive.x1),
        checkedCoordinate(primitive.y1),
        checkedCoordinate(primitive.x2),
        checkedCoordinate(primitive.y2),
        checkedInteger(primitive.width, 1, 8, "line width"),
        ink,
      );
    } else if (primitive.kind === "rect") {
      rectangle(
        pixels,
        width,
        height,
        checkedCoordinate(primitive.x),
        checkedCoordinate(primitive.y),
        checkedInteger(primitive.width, 1, 1200, "rectangle width"),
        checkedInteger(primitive.height, 1, 1200, "rectangle height"),
        ink,
      );
    } else if (primitive.kind === "triangle") {
      triangle(
        pixels,
        width,
        height,
        checkedCoordinate(primitive.x1),
        checkedCoordinate(primitive.y1),
        checkedCoordinate(primitive.x2),
        checkedCoordinate(primitive.y2),
        checkedCoordinate(primitive.x3),
        checkedCoordinate(primitive.y3),
        ink,
      );
    } else {
      throw new Error("unsupported render primitive");
    }
  }

  const stride = width * 4 + 1;
  const raw = new Uint8Array(stride * height);
  for (let y = 0; y < height; y += 1) {
    raw[y * stride] = 0;
    raw.set(pixels.subarray(y * width * 4, (y + 1) * width * 4), y * stride + 1);
  }

  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 6;
  header[10] = 0;
  header[11] = 0;
  header[12] = 0;
  return Buffer.concat([
    signature,
    chunk("IHDR", header),
    chunk("IDAT", deflateSync(raw, { level: 9 })),
    chunk("IEND", Buffer.alloc(0)),
  ]).toString("base64");
}

function checkedInteger(value, minimum, maximum, field) {
  if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
    throw new Error(`invalid ${field}`);
  }
  return value;
}

function checkedCoordinate(value) {
  return checkedInteger(value, -2400, 2400, "coordinate");
}

function color(value) {
  if (typeof value !== "string" || !/^#[0-9a-f]{6}$/.test(value)) {
    throw new Error("invalid render color");
  }
  return [
    Number.parseInt(value.slice(1, 3), 16),
    Number.parseInt(value.slice(3, 5), 16),
    Number.parseInt(value.slice(5, 7), 16),
  ];
}

function setPixel(pixels, width, height, x, y, ink) {
  if (x < 0 || y < 0 || x >= width || y >= height) return;
  const offset = (y * width + x) * 4;
  pixels[offset] = ink[0];
  pixels[offset + 1] = ink[1];
  pixels[offset + 2] = ink[2];
  pixels[offset + 3] = 255;
}

function rectangle(pixels, width, height, x, y, rectWidth, rectHeight, ink) {
  const startX = Math.max(x, 0);
  const startY = Math.max(y, 0);
  const endX = Math.min(x + rectWidth, width);
  const endY = Math.min(y + rectHeight, height);
  for (let row = startY; row < endY; row += 1) {
    for (let column = startX; column < endX; column += 1) {
      setPixel(pixels, width, height, column, row, ink);
    }
  }
}

function line(pixels, width, height, x1, y1, x2, y2, thickness, ink) {
  let x = x1;
  let y = y1;
  const dx = Math.abs(x2 - x1);
  const sx = x1 < x2 ? 1 : -1;
  const dy = -Math.abs(y2 - y1);
  const sy = y1 < y2 ? 1 : -1;
  let error = dx + dy;
  const offset = Math.floor(thickness / 2);
  while (true) {
    rectangle(pixels, width, height, x - offset, y - offset, thickness, thickness, ink);
    if (x === x2 && y === y2) break;
    const doubled = error * 2;
    if (doubled >= dy) {
      error += dy;
      x += sx;
    }
    if (doubled <= dx) {
      error += dx;
      y += sy;
    }
  }
}

function triangle(pixels, width, height, x1, y1, x2, y2, x3, y3, ink) {
  const minimumX = Math.max(Math.min(x1, x2, x3), 0);
  const maximumX = Math.min(Math.max(x1, x2, x3), width - 1);
  const minimumY = Math.max(Math.min(y1, y2, y3), 0);
  const maximumY = Math.min(Math.max(y1, y2, y3), height - 1);
  const edge = (ax, ay, bx, by, px, py) => (px - ax) * (by - ay) - (py - ay) * (bx - ax);
  for (let y = minimumY; y <= maximumY; y += 1) {
    for (let x = minimumX; x <= maximumX; x += 1) {
      const a = edge(x1, y1, x2, y2, x, y);
      const b = edge(x2, y2, x3, y3, x, y);
      const c = edge(x3, y3, x1, y1, x, y);
      if ((a >= 0 && b >= 0 && c >= 0) || (a <= 0 && b <= 0 && c <= 0)) {
        setPixel(pixels, width, height, x, y, ink);
      }
    }
  }
}

function chunk(type, data) {
  const typeBytes = Buffer.from(type, "ascii");
  const body = Buffer.from(data);
  const output = Buffer.alloc(12 + body.length);
  output.writeUInt32BE(body.length, 0);
  typeBytes.copy(output, 4);
  body.copy(output, 8);
  output.writeUInt32BE(crc32(Buffer.concat([typeBytes, body])), 8 + body.length);
  return output;
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit += 1) {
      crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}
