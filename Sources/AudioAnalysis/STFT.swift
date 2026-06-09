import Accelerate

/// Streaming short-time Fourier transform: push mono samples in any chunk
/// size, get a 512-bin magnitude spectrum per 256-sample hop.
final class STFT {
    static let fftSize = 1024
    static let hop = 256
    static let binCount = 512

    private let setup: FFTSetup
    private let window: [Float]
    private var realp = [Float](repeating: 0, count: 512)
    private var imagp = [Float](repeating: 0, count: 512)
    private var frame = [Float](repeating: 0, count: fftSize)
    private var pending: [Float] = []

    /// Number of hops emitted so far (frame index of the *next* spectrum).
    private(set) var framesEmitted = 0

    init() {
        setup = vDSP_create_fftsetup(10, FFTRadix(kFFTRadix2))!
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized,
                             count: Self.fftSize, isHalfWindow: false)
        pending.reserveCapacity(Self.fftSize * 4)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// Feeds samples; calls `emit` once per completed hop with the magnitude
    /// spectrum (length 512; bin i covers frequency i·sr/1024).
    func process(_ samples: UnsafeBufferPointer<Float>, emit: ([Float]) -> Void) {
        pending.append(contentsOf: samples)
        var offset = 0
        while pending.count - offset >= Self.fftSize {
            pending.withUnsafeBufferPointer { buf in
                vDSP.multiply(UnsafeBufferPointer(rebasing: buf[offset..<(offset + Self.fftSize)]),
                              window, result: &frame)
            }
            emit(magnitudes())
            offset += Self.hop
            framesEmitted += 1
        }
        if offset > 0 {
            pending.removeFirst(offset)
        }
    }

    private func magnitudes() -> [Float] {
        var mags = [Float](repeating: 0, count: Self.binCount)
        realp.withUnsafeMutableBufferPointer { rp in
            imagp.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                frame.withUnsafeBufferPointer { f in
                    f.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: Self.binCount) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(Self.binCount))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, 10, FFTDirection(FFT_FORWARD))
                vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(Self.binCount))
            }
        }
        mags[0] = abs(realp[0]) // DC (packed real); Nyquist (imagp[0]) ignored
        return mags
    }
}
