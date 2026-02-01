import CoreML
import Vision

// MARK: - Placeholders for Compilation
// These classes simulate the generated CoreML model classes.
// Users should delete this file or comment it out once they add the actual .mlpackage files to Xcode.

#if !canImport(RMBG14)
class RMBG14 {
    var model: MLModel
    
    init(configuration: MLModelConfiguration = MLModelConfiguration()) throws {
        self.model = MLModel() // Dummy
    }
    
    func prediction(input: RMBG14Input) throws -> RMBG14Output {
        return RMBG14Output()
    }
}

class RMBG14Input {
    var input: CVPixelBuffer
    
    init(input: CVPixelBuffer) {
        self.input = input
    }
}

class RMBG14Output {
    var output: CVPixelBuffer {
        // Return 1x1 dummy buffer
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, 1, 1, kCVPixelFormatType_32BGRA, nil, &pixelBuffer)
        return pixelBuffer!
    }
}
#endif

#if !canImport(MobileSAM_Encoder)
class MobileSAM_Encoder {
    var model: MLModel
    
    init(configuration: MLModelConfiguration = MLModelConfiguration()) throws {
        self.model = MLModel()
    }
    
    func prediction(image: CVPixelBuffer) throws -> MobileSAM_EncoderOutput {
        return MobileSAM_EncoderOutput()
    }
}

class MobileSAM_EncoderOutput {
    var image_embeddings: MLMultiArray {
        return try! MLMultiArray(shape: [1, 256, 64, 64], dataType: .float32)
    }
}
#endif
