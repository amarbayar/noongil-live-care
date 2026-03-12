import CoreImage

struct CameraFilterPipeline {
    static let availableFilters = ["none", "warm", "cool", "vintage", "noir", "vivid"]

    static func apply(filterName: String, to image: CIImage) -> CIImage {
        switch filterName {
        case "warm":
            return applyTemperature(to: image, neutral: 5500, target: 6500)
        case "cool":
            return applyTemperature(to: image, neutral: 6500, target: 4500)
        case "vintage":
            return applySepia(to: image, intensity: 0.7)
        case "noir":
            return applyNoir(to: image)
        case "vivid":
            return applyVivid(to: image)
        default:
            return image
        }
    }

    // MARK: - Filters

    private static func applyTemperature(to image: CIImage, neutral: Float, target: Float) -> CIImage {
        guard let filter = CIFilter(name: "CITemperatureAndTint") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(x: CGFloat(neutral), y: 0), forKey: "inputNeutral")
        filter.setValue(CIVector(x: CGFloat(target), y: 0), forKey: "inputTargetNeutral")
        return filter.outputImage ?? image
    }

    private static func applySepia(to image: CIImage, intensity: Double) -> CIImage {
        guard let filter = CIFilter(name: "CISepiaTone") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(intensity, forKey: kCIInputIntensityKey)
        return filter.outputImage ?? image
    }

    private static func applyNoir(to image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIPhotoEffectNoir") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        return filter.outputImage ?? image
    }

    private static func applyVivid(to image: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(1.5, forKey: kCIInputSaturationKey)
        filter.setValue(0.05, forKey: kCIInputBrightnessKey)
        filter.setValue(1.1, forKey: kCIInputContrastKey)
        return filter.outputImage ?? image
    }
}
