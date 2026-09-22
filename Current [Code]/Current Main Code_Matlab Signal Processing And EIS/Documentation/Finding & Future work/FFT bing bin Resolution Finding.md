Peak Frequency (bin, uncorrected):      1999.000499 Hz
Peak Frequency (parabolic-corrected):   1864.500706 Hz  (delta = -0.2691 bins)

This confirms it — and it's a much bigger problem than I initially suspected. Look at the bin width
in the title: 499.75 Hz per bin.

That's enormous. Your true signal is ~1999 Hz, but each FFT bin is nearly 500 Hz wide, so the
whole spectrum only has bins at roughly 0, 500, 1000, 1500, 2000, 2500, 3000 Hz... Your true
peak at 1999 Hz doesn't land near a bin, it lands almost exactly between the 1500 Hz bin
(amplitude 2.87) and the 2000 Hz bin (amplitude 3.7, picked as peak). Look at how tall the
"wrong side" neighbor is: the 1500 Hz bin at amplitude 2.87 is nearly as tall as the peak itself
(3.7) — that's not a small shoulder, that's two comparably-sized bins straddling the true
frequency.

This is a completely different, more fundamental problem than leakage. Parabolic
interpolation is only valid when the bin spacing is fine relative to how far off-grid the true
frequency is — it assumes the two neighbor bins are much smaller than the peak, tapering off in
the classic mainlobe shape. Here the neighbor is almost the same height as the peak. The
three-point parabola fit through (2.87, 3.7, 0.97) is being wildly distorted by that asymmetry —
which is exactly why it dragged the estimate to 1864 Hz instead of correcting it toward
~1999-2000.

Why is the bin width so huge (500 Hz)? Bin width = Fs/N. This file only has enough samples
for a very short window at this sample rate — go check: for this file, what are Fs and N? From
your earlier log, this file processed 2001 total samples (4PSF | pass1: 2001/2001). At
whatever Fs you're sampling at, that gives you a very short recording — probably only 1-4
cycles of a 2 kHz signal — hence the coarse 500 Hz bins.

This changes the fix. Parabolic interpolation can't rescue a spectrum this coarse — the
fundamental problem is not enough samples/cycles recorded at this frequency to resolve it via
FFT at all. A few options, in order of how much I'd trust them:

1.  Zero-padding the FFT — pad signal_noDC with zeros to a much longer length before
the FFT. This doesn't add real information, but it interpolates the existing spectrum onto
a much finer bin grid, which makes the parabola fit (now fitting a well-sampled sinc
mainlobe instead of 3 widely-spaced points) far more reliable. Cheap, easy, and directly
fixes what you're seeing here.

2.  Reject/cap the correction when the neighbor-to-peak ratio is too extreme — e.g. if
min(alpha,gamma)/beta > 0.5 (neighbor is more than half the peak height), the
peak is too close to bin-edge for a 3-point parabola to trust; flag it rather than silently
applying a bad correction.

3.  Go back to 4PSF/Gauss-Newton as the real fix here — since this file's real problem is

"FFT can't resolve this well at all," the time-domain fit (4PSF) is actually the more
appropriate tool for finding f0 in this specific case, not FFT+parabola. But we already
saw Gauss-Newton also drifted here (1864→1794, still wrong), likely for the same
underlying reason: too few cycles recorded, so the time-domain fit is also poorly
constrained.

