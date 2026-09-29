<?php

namespace App\Support;

/**
 * Geometry for a small multi-series line chart, drawn as inline SVG.
 *
 * No chart library: the console has no build step (Tailwind comes from the
 * Play CDN), and one fourteen-point trend does not justify a JavaScript
 * dependency. The server works out every coordinate here and the Blade view
 * only places them, so the chart renders complete with JavaScript switched off.
 *
 * Coordinates come in two forms, because the chart is drawn in two layers:
 *
 *  - the lines and filled areas are SVG paths in a fixed 1000 x 300 viewBox,
 *    stretched to the card's width (`preserveAspectRatio="none"`, with
 *    non-scaling strokes so the lines stay crisp at any width);
 *  - the dots, axis labels and hover targets are HTML, placed by percentage.
 *    Circles drawn inside a stretched SVG would come out as ovals.
 */
final class LineChart
{
    public const WIDTH = 1000;

    public const HEIGHT = 300;

    /** @var array<string, list<int|float>> */
    private array $series;

    private int $points;

    private float $max;

    private float $step;

    /**
     * @param  array<string, list<int|float>>  $series  Name => one value per point.
     *                                                  Every series the same length.
     */
    public function __construct(array $series)
    {
        $this->series = array_map(fn (array $values) => array_values(array_map('floatval', $values)), $series);
        // array_values: spreading a string-keyed array into max() would pass
        // the series names as named arguments, which max() rejects.
        $this->points = max(0, ...array_values(array_map('count', $this->series)));

        $peak = max(0, ...array_merge([0], ...array_values($this->series)));
        [$this->max, $this->step] = self::niceScale($peak);
    }

    /** The value at the top of the y axis. Always above zero. */
    public function max(): float
    {
        return $this->max;
    }

    /**
     * Gridline values from 0 to [max], bottom first.
     *
     * @return list<float>
     */
    public function ticks(): array
    {
        $ticks = [];
        for ($v = 0.0; $v <= $this->max + 1e-9; $v += $this->step) {
            $ticks[] = round($v, 6);
        }

        return $ticks;
    }

    public function count(): int
    {
        return $this->points;
    }

    /** Horizontal position of point $i, as a percentage of the plot width. */
    public function xPercent(int $i): float
    {
        return $this->points <= 1 ? 50.0 : $i / ($this->points - 1) * 100;
    }

    /** Vertical position of $value, as a percentage from the top of the plot. */
    public function yPercent(float $value): float
    {
        return (1 - $value / $this->max) * 100;
    }

    /** The series as a smooth SVG path in the 1000 x 300 viewBox. */
    public function line(string $name): string
    {
        $points = $this->svgPoints($name);

        if ($points === []) {
            return '';
        }

        return 'M'.self::pair($points[0]).self::curve($points);
    }

    /** The same curve closed along the x axis, for the shaded area under it. */
    public function area(string $name): string
    {
        $points = $this->svgPoints($name);

        if ($points === []) {
            return '';
        }

        $first = $points[0];
        $last = $points[count($points) - 1];

        return 'M'.self::pair([$first[0], self::HEIGHT])
            .'L'.self::pair($first)
            .self::curve($points)
            .'L'.self::pair([$last[0], self::HEIGHT]).'Z';
    }

    /**
     * Rounds the axis up to a number people read easily - 4, 10, 20, 50 -
     * split into at most five equal steps. An axis topped at the raw peak
     * (say 13) gives gridlines at 3.25 and 6.5, which nobody can read.
     *
     * @return array{0: float, 1: float} [max, step]
     */
    public static function niceScale(float $peak): array
    {
        // Counts are whole numbers, so a quiet fortnight still gets a 0-4
        // axis in steps of 1 rather than steps of 0.25.
        if ($peak <= 4) {
            return [4.0, 1.0];
        }

        $rough = $peak / 4;
        $magnitude = 10 ** floor(log10($rough));
        $normalised = $rough / $magnitude;

        $step = match (true) {
            $normalised <= 1 => 1,
            $normalised <= 2 => 2,
            $normalised <= 5 => 5,
            default => 10,
        } * $magnitude;

        $step = max(1.0, $step);

        return [ceil($peak / $step) * $step, $step];
    }

    /** @return list<array{0: float, 1: float}> */
    private function svgPoints(string $name): array
    {
        $values = $this->series[$name] ?? [];
        $points = [];

        foreach ($values as $i => $value) {
            $points[] = [
                $this->xPercent($i) / 100 * self::WIDTH,
                $this->yPercent($value) / 100 * self::HEIGHT,
            ];
        }

        return $points;
    }

    /**
     * Cubic segments through every point, using monotone interpolation
     * (Fritsch-Carlson - the same as d3's `curveMonotoneX`).
     *
     * Why not an ordinary smooth curve: a Catmull-Rom or Bezier fit overshoots.
     * Between two quiet days either side of a busy one it swings BELOW the
     * zero line, drawing a day with negative jobs. Monotone interpolation
     * never goes past the values it connects, so every bend in the line is
     * one the data actually has.
     *
     * @param  list<array{0: float, 1: float}>  $p
     */
    private static function curve(array $p): string
    {
        $n = count($p);

        if ($n < 2) {
            return '';
        }

        if ($n === 2) {
            return 'L'.self::pair($p[1]);
        }

        // Slope of each segment, then a tangent at each point.
        $d = [];
        for ($k = 0; $k < $n - 1; $k++) {
            $d[$k] = ($p[$k + 1][1] - $p[$k][1]) / ($p[$k + 1][0] - $p[$k][0]);
        }

        $m = [$d[0]];
        for ($k = 1; $k < $n - 1; $k++) {
            // A peak or a valley gets a flat tangent, so the curve turns there
            // instead of carrying on past the point.
            $m[$k] = $d[$k - 1] * $d[$k] <= 0 ? 0.0 : ($d[$k - 1] + $d[$k]) / 2;
        }
        $m[$n - 1] = $d[$n - 2];

        // Rein in tangents steep enough to overshoot.
        for ($k = 0; $k < $n - 1; $k++) {
            if ($d[$k] == 0.0) {
                $m[$k] = 0.0;
                $m[$k + 1] = 0.0;

                continue;
            }

            $a = $m[$k] / $d[$k];
            $b = $m[$k + 1] / $d[$k];
            $h = $a * $a + $b * $b;

            if ($h > 9) {
                $t = 3 / sqrt($h);
                $m[$k] = $t * $a * $d[$k];
                $m[$k + 1] = $t * $b * $d[$k];
            }
        }

        $path = '';
        for ($k = 0; $k < $n - 1; $k++) {
            $dx = ($p[$k + 1][0] - $p[$k][0]) / 3;
            $path .= 'C'.self::pair([$p[$k][0] + $dx, $p[$k][1] + $m[$k] * $dx])
                .' '.self::pair([$p[$k + 1][0] - $dx, $p[$k + 1][1] - $m[$k + 1] * $dx])
                .' '.self::pair($p[$k + 1]);
        }

        return $path;
    }

    /** @param  array{0: float, 1: float}  $point */
    private static function pair(array $point): string
    {
        return round($point[0], 2).','.round($point[1], 2);
    }
}
