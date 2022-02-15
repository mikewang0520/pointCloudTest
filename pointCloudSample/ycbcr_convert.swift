import Accelerate
import CoreGraphics
import CoreMedia
import Foundation
import QuartzCore
import UIKit

func createImage(_ imageBuffer: CVPixelBuffer) -> UIImage? {
//    guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
//      return nil
//    }

    // pixel format is Bi-Planar Component Y'CbCr 8-bit 4:2:0, full-range (luma=[0,255] chroma=[1,255]).
    // baseAddr points to a big-endian CVPlanarPixelBufferInfo_YCbCrBiPlanar struct.
    //
    guard CVPixelBufferGetPixelFormatType(imageBuffer) == kCVPixelFormatType_420YpCbCr8BiPlanarFullRange else {
        return nil
    }


    guard CVPixelBufferLockBaseAddress(imageBuffer, .readOnly) == kCVReturnSuccess else {
        return nil
    }

    defer {
        // be sure to unlock the base address before returning
        CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly)
    }

    // 1st plane is luminance, 2nd plane is chrominance
    guard CVPixelBufferGetPlaneCount(imageBuffer) == 2 else {
        return nil
    }

    // 1st plane
    guard let lumaBaseAddress = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0) else {
        return nil
    }

    let lumaWidth = CVPixelBufferGetWidthOfPlane(imageBuffer, 0)
    let lumaHeight = CVPixelBufferGetHeightOfPlane(imageBuffer, 0)
    let lumaBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0)
    var lumaBuffer = vImage_Buffer(
        data: lumaBaseAddress,
        height: vImagePixelCount(lumaHeight),
        width: vImagePixelCount(lumaWidth),
        rowBytes: lumaBytesPerRow
    )

    // 2nd plane
    guard let chromaBaseAddress = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 1) else {
        return nil
    }

    let chromaWidth = CVPixelBufferGetWidthOfPlane(imageBuffer, 1)
    let chromaHeight = CVPixelBufferGetHeightOfPlane(imageBuffer, 1)
    let chromaBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 1)
    var chromaBuffer = vImage_Buffer(
        data: chromaBaseAddress,
        height: vImagePixelCount(chromaHeight),
        width: vImagePixelCount(chromaWidth),
        rowBytes: chromaBytesPerRow
    )

    var argbBuffer = vImage_Buffer()

    defer {
        // we are responsible for freeing the buffer data
        free(argbBuffer.data)
    }

    // initialize the empty buffer
    guard vImageBuffer_Init(
        &argbBuffer,
        lumaBuffer.height,
        lumaBuffer.width,
        32,
        vImage_Flags(kvImageNoFlags)
        ) == kvImageNoError else {
            return nil
    }

    // full range 8-bit, clamped to full range, is necessary for correct color reproduction
    var pixelRange = vImage_YpCbCrPixelRange(
        Yp_bias: 0,
        CbCr_bias: 128,
        YpRangeMax: 255,
        CbCrRangeMax: 255,
        YpMax: 255,
        YpMin: 1,
        CbCrMax: 255,
        CbCrMin: 0
    )

    var conversionInfo = vImage_YpCbCrToARGB()

    // initialize the conversion info
    guard vImageConvert_YpCbCrToARGB_GenerateConversion(
        kvImage_YpCbCrToARGBMatrix_ITU_R_601_4, // Y'CbCr-to-RGB conversion matrix for ITU Recommendation BT.601-4.
        &pixelRange,
        &conversionInfo,
        kvImage420Yp8_CbCr8, // converting from
        kvImageARGB8888, // converting to
        vImage_Flags(kvImageNoFlags)
        ) == kvImageNoError else {
            return nil
    }

    // do the conversion
    guard vImageConvert_420Yp8_CbCr8ToARGB8888(
        &lumaBuffer, // in
        &chromaBuffer, // in
        &argbBuffer, // out
        &conversionInfo,
        nil,
        255,
        vImage_Flags(kvImageNoFlags)
        ) == kvImageNoError else {
            return nil
    }

    // core foundation objects are automatically memory mananged. no need to call CGContextRelease() or CGColorSpaceRelease()
    guard let context = CGContext(
        data: argbBuffer.data,
        width: Int(argbBuffer.width),
        height: Int(argbBuffer.height),
        bitsPerComponent: 8,
        bytesPerRow: argbBuffer.rowBytes,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            return nil
    }

    guard let cgImage = context.makeImage() else {
        return nil
    }

    return UIImage(cgImage: cgImage)
}
