<?php

namespace Tests\Unit;

use App\Support\LineChart;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

class LineChartTest extends TestCase
{
    /** @return array<string, array{0: float, 1: float, 2: float}> */
    public static function scales(): array
    {
        return [
            'empty fortnight' => [0, 4, 1],
            'quiet fortnight' => [3, 4, 1],
            'just above four' => [5, 6, 2],
            'thirteen' => [13, 15, 5],
            'busy' => [64, 80, 20],
            'exact step' => [20, 20, 5],
        ];
    }

    #[DataProvider('scales')]
    public function test_axis_rounds_up_to_a_readable_number(float $peak, float $max, float $step): void
    {
        $this->assertSame([$max, $step], LineChart::niceScale($peak));
    }

    public function test_ticks_run_from_zero_to_the_top_of_the_axis(): void
    {
        $chart = new LineChart(['posted' => [2, 13, 7]]);

        $this->assertSame([0.0, 5.0, 10.0, 15.0], $chart->ticks());
        $this->assertSame(15.0, $chart->max());
    }

    /**
     * The reason the curve is monotone: a spike between quiet days must not
     * dip below the zero line on either side of it.
     */
    public function test_the_curve_never_goes_below_zero_or_above_the_peak(): void
    {
        $chart = new LineChart(['posted' => [0, 0, 9, 0, 1, 0, 0]]);

        $top = $chart->yPercent(9) / 100 * LineChart::HEIGHT;

        foreach ($this->ys($chart->line('posted')) as $y) {
            $this->assertLessThanOrEqual(LineChart::HEIGHT + 1e-6, $y, 'curve dips below zero');
            $this->assertGreaterThanOrEqual($top - 1e-6, $y, 'curve overshoots the peak');
        }
    }

    public function test_points_span_the_full_width(): void
    {
        $chart = new LineChart(['posted' => array_fill(0, 14, 1)]);

        $this->assertSame(0.0, $chart->xPercent(0));
        $this->assertSame(100.0, $chart->xPercent(13));
        $this->assertSame(14, $chart->count());
    }

    public function test_the_area_is_closed_along_the_baseline(): void
    {
        $area = (new LineChart(['done' => [1, 3, 2]]))->area('done');

        $this->assertStringStartsWith('M0,300L', $area);
        $this->assertStringEndsWith('L1000,300Z', $area);
    }

    public function test_an_unknown_series_draws_nothing(): void
    {
        $chart = new LineChart(['posted' => [1, 2]]);

        $this->assertSame('', $chart->line('missing'));
        $this->assertSame('', $chart->area('missing'));
    }

    /** @return list<float> Every y coordinate in a path, control points included. */
    private function ys(string $path): array
    {
        preg_match_all('/(-?[\d.]+),(-?[\d.]+)/', $path, $m);

        return array_map('floatval', $m[2]);
    }
}
