#!/usr/bin/env python3

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

BASE_WIDTH = 680
BASE_HEIGHT = 430


def scale(value: int, factor: int) -> int:
    return value * factor


def lerp(a: int, b: int, t: float) -> int:
    return round(a + (b - a) * t)


def lerp_color(start: tuple[int, int, int], end: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(lerp(sa, ea, t) for sa, ea in zip(start, end))


def draw_vertical_gradient(image: Image.Image, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> None:
    draw = ImageDraw.Draw(image)
    for y in range(image.height):
        t = y / max(image.height - 1, 1)
        draw.line([(0, y), (image.width, y)], fill=lerp_color(top, bottom, t))


def add_glow(
    image: Image.Image,
    center: tuple[int, int],
    size: tuple[int, int],
    color: tuple[int, int, int],
    alpha: int,
    blur: int,
) -> None:
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    left = center[0] - size[0] // 2
    top = center[1] - size[1] // 2
    right = left + size[0]
    bottom = top + size[1]
    draw.ellipse((left, top, right, bottom), fill=(*color, alpha))
    layer = layer.filter(ImageFilter.GaussianBlur(blur))
    image.alpha_composite(layer)


def arrow_points(width: int, height: int) -> list[tuple[int, int]]:
    return [
        (int(width * 0.08), int(height * 0.34)),
        (int(width * 0.54), int(height * 0.34)),
        (int(width * 0.54), int(height * 0.16)),
        (int(width * 0.95), int(height * 0.50)),
        (int(width * 0.54), int(height * 0.84)),
        (int(width * 0.54), int(height * 0.66)),
        (int(width * 0.08), int(height * 0.66)),
    ]


def arrow_gradient(width: int, height: int) -> Image.Image:
    gradient = Image.new("RGBA", (width, height))
    pixels = gradient.load()
    left = (100, 235, 236)
    middle = (110, 184, 255)
    right = (118, 104, 255)

    for x in range(width):
        t = x / max(width - 1, 1)
        if t < 0.6:
            color = lerp_color(left, middle, t / 0.6)
        else:
            color = lerp_color(middle, right, (t - 0.6) / 0.4)
        for y in range(height):
            pixels[x, y] = (*color, 255)

    return gradient


def add_arrow(image: Image.Image, origin: tuple[int, int], size: tuple[int, int], factor: int) -> None:
    x0, y0 = origin
    width, height = size
    mask = Image.new("L", (width, height), 0)
    mask_draw = ImageDraw.Draw(mask)
    points = arrow_points(width, height)
    mask_draw.polygon(points, fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(max(1, scale(1, factor))))

    shadow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    shadow_arrow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    shadow_arrow.putalpha(mask)
    shadow.paste((48, 60, 104, 72), (x0 + scale(3, factor), y0 + scale(7, factor)), shadow_arrow)
    shadow = shadow.filter(ImageFilter.GaussianBlur(scale(8, factor)))
    image.alpha_composite(shadow)

    halo = Image.new("RGBA", image.size, (0, 0, 0, 0))
    halo_arrow = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    halo_arrow.putalpha(mask)
    halo.paste((132, 227, 255, 44), (x0, y0), halo_arrow)
    halo = halo.filter(ImageFilter.GaussianBlur(scale(8, factor)))
    image.alpha_composite(halo)

    arrow = Image.new("RGBA", image.size, (0, 0, 0, 0))
    gradient = arrow_gradient(width, height)
    arrow.paste(gradient, (x0, y0), mask)

    draw = ImageDraw.Draw(arrow)
    translated_points = [(x0 + px, y0 + py) for px, py in points]
    draw.polygon(
        translated_points,
        outline=(233, 251, 255, 152),
        width=max(scale(2, factor), 2),
    )
    image.alpha_composite(arrow)


def add_border(image: Image.Image, factor: int) -> None:
    inset = scale(18, factor)
    layer = Image.new("RGBA", image.size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    draw.rounded_rectangle(
        (inset, inset, image.width - inset, image.height - inset),
        radius=scale(24, factor),
        outline=(255, 255, 255, 50),
        width=max(scale(2, factor), 2),
    )
    image.alpha_composite(layer)


def render_background(factor: int) -> Image.Image:
    width = BASE_WIDTH * factor
    height = BASE_HEIGHT * factor
    image = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    draw_vertical_gradient(image, (244, 247, 255), (234, 242, 255))

    add_glow(
        image,
        (scale(178, factor), scale(238, factor)),
        (scale(180, factor), scale(180, factor)),
        (106, 236, 229),
        48,
        scale(28, factor),
    )
    add_glow(
        image,
        (scale(504, factor), scale(236, factor)),
        (scale(188, factor), scale(188, factor)),
        (126, 170, 255),
        56,
        scale(30, factor),
    )
    add_glow(
        image,
        (scale(340, factor), scale(132, factor)),
        (scale(180, factor), scale(92, factor)),
        (134, 114, 255),
        36,
        scale(26, factor),
    )

    add_arrow(
        image,
        (scale(258, factor), scale(181, factor)),
        (scale(164, factor), scale(68, factor)),
        factor,
    )
    add_border(image, factor)
    return image


def main() -> None:
    parser = argparse.ArgumentParser(description="Render the Octowatch DMG background.")
    parser.add_argument("--output", required=True, help="Output PNG path")
    parser.add_argument("--scale", type=int, default=1, choices=(1, 2), help="Render scale factor")
    args = parser.parse_args()

    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    render_background(args.scale).save(output_path, format="PNG")


if __name__ == "__main__":
    main()
