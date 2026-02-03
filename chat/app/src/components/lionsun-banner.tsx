import React, { useEffect, useRef } from 'react';

// themes: emptiness vs expectation, natural self-sufficiency, action through non-action
// visualization: Binary patterns that naturally erode and flow, demonstrating how emptiness enables movement

const LIONSUN_SHAPE = [
  '                 .    |     .                  ',
  '                  \\   |    /                   ',
  "      \\|\\||    .   \\  '   /   .'               ",
  '     -- ||||/   `. .-*""*-. .\'                 ',
  '    /7   |||||/._ /        \\ _.-*"             ',
  '   /    |||||||/.:          ;                  ',
  "   \\-' |||||||||-----------------._            ",
  '    -/||||||||\\                `` -`.          ',
  '      /||||||\\             \\_  |   `\\\\         ',
  "      -//|||\\|________...---'\\  \\    \\\\        ",
  '         ||  |  \\ ``-.__--. | \\  |    ``-.__--.',
  "        / |  |\\  \\   ``---'/ / | |       ``---'",
  '     __/_/  / _|  )     __/ / _| |             ',
  '    /,_/,__/_/,__/     /,__/ /,__/             '
];

const WIDTH = 52;
const HEIGHT = 22;
const BLOCK_SIZE = 18;
const FRAME_SKIP = 3;

const buildShapeMask = () => {
  const shapeWidth = Math.max(...LIONSUN_SHAPE.map((line) => line.length));
  const shapeHeight = LIONSUN_SHAPE.length;
  const offsetX = Math.floor((WIDTH - shapeWidth) / 2);
  const offsetY = Math.floor((HEIGHT - shapeHeight) / 2);
  const mask = Array.from({ length: HEIGHT }, () => Array.from({ length: WIDTH }, () => false));

  for (let y = 0; y < shapeHeight; y += 1) {
    const row = LIONSUN_SHAPE[y] || '';
    for (let x = 0; x < row.length; x += 1) {
      if (row[x] !== ' ') {
        const targetX = x + offsetX;
        const targetY = y + offsetY;
        if (targetX >= 0 && targetX < WIDTH && targetY >= 0 && targetY < HEIGHT) {
          mask[targetY][targetX] = true;
        }
      }
    }
  }

  return mask;
};

export default function LionsunBanner() {
  const canvasRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return undefined;

    let grid: string[][] = [];
    let time = 0;
    let frame = 0;
    let animationFrameId = 0;
    const shapeMask = buildShapeMask();

    const initGrid = () => {
      grid = Array.from({ length: HEIGHT }, () => Array.from({ length: WIDTH }, () => ' '));
    };

    const render = () => {
      let html = '';
      for (let y = 0; y < HEIGHT; y += 1) {
        for (let x = 0; x < WIDTH; x += 1) {
          html += grid[y][x];
        }
        html += '<br>';
      }
      canvas.innerHTML = html;
    };

    const update = () => {
      initGrid();

      const blockX = Math.floor(WIDTH / 2 - BLOCK_SIZE / 2);
      const blockY = Math.floor(HEIGHT / 2 - BLOCK_SIZE / 2);
      const t = time * 0.003;

      for (let y = 0; y < HEIGHT; y += 1) {
        for (let x = 0; x < WIDTH; x += 1) {
          if (shapeMask[y][x]) {
            const innerDist = Math.min(
              x - blockX,
              blockX + BLOCK_SIZE - x,
              y - blockY,
              blockY + BLOCK_SIZE - y
            );
            const erosion = time * 0.003;
            grid[y][x] = innerDist > erosion ? '#' : Math.random() > 0.9 ? '1' : '0';
            continue;
          }

          const dx = x - WIDTH / 2;
          const dy = y - HEIGHT / 2;
          const angle = Math.atan2(dy, dx);
          const dist = Math.sqrt(dx * dx + dy * dy);
          const wave = Math.sin(dist * 0.2 - t + angle * 1.5);
          const flow = Math.sin(x * 0.08 + y * 0.04 + t * 0.4);

          if (flow + wave > 0.65) {
            grid[y][x] = '.';
          } else if (flow + wave < -0.65) {
            grid[y][x] = '~';
          }
        }
      }

      time += 1;
    };

    const animate = () => {
      frame += 1;
      if (frame % FRAME_SKIP === 0) {
        update();
        render();
      }
      animationFrameId = requestAnimationFrame(animate);
    };

    initGrid();
    animationFrameId = requestAnimationFrame(animate);

    return () => {
      if (animationFrameId) cancelAnimationFrame(animationFrameId);
      if (canvas) canvas.innerHTML = '';
    };
  }, []);

  return (
    <div
      aria-label="Sunlion banner"
      className="mx-auto w-fit rounded-xl border border-border bg-background px-3 py-2 select-none"
    >
      <div
        ref={canvasRef}
        className="banner-sunlion text-muted-foreground"
        style={{
          lineHeight: '0.85',
          letterSpacing: '0.08em',
          fontFamily: 'monospace',
          fontSize: '7px',
          width: '52ch',
          height: '22em',
          overflow: 'hidden',
          display: 'block',
          userSelect: 'none',
          color: 'hsl(var(--muted-foreground))'
        }}
      />
    </div>
  );
}
